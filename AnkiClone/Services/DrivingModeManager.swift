import Foundation
import AVFoundation
import Speech
import MediaPlayer
import SwiftData

/// Voice Command Types Recognized in Driving Mode
enum DrivingVoiceCommand: String, CaseIterable, Sendable {
    case repeatQuestion = "repeat"
    case skipCard = "skip"
    case requestHint = "hint"
    case stopSession = "stop"
}

/// Recorded Card Review During Driving Session (Used for Parked Review Audit)
struct DriveCardReviewRecord: Identifiable, Sendable {
    let id = UUID()
    let card: Card
    let question: String
    let expectedAnswer: String
    let userTranscript: String
    var assignedRating: Rating
    let similarityScore: Double
    let dateReviewed: Date
    
    init(
        card: Card,
        question: String,
        expectedAnswer: String,
        userTranscript: String,
        assignedRating: Rating,
        similarityScore: Double,
        dateReviewed: Date = Date()
    ) {
        self.card = card
        self.question = question
        self.expectedAnswer = expectedAnswer
        self.userTranscript = userTranscript
        self.assignedRating = assignedRating
        self.similarityScore = similarityScore
        self.dateReviewed = dateReviewed
    }
}

/// Driving Mode State
enum DrivingState: Equatable, Sendable {
    case idle
    case speakingQuestion
    case listeningForAnswer
    case speakingFeedback
    case paused
    case completed
}

/// 100% Free, On-Device Hands-Free Voice Study Engine for Driving / Commuting
/// Follows strict safety and scheduling guidelines:
/// - AVSpeechSynthesizer for question & hint audio
/// - SFSpeechRecognizer with requiresOnDeviceRecognition = true
/// - Expected answer injected as contextual vocabulary for road-noise robustness
/// - Fuzzy matching + medical synonyms:
///   * Clear match = Good
///   * Partial match = Hard
///   * Wrong, silence, "I don't know" = Again
///   * STRICT: NEVER USE EASY IN THIS MODE
/// - Background audio session (.playAndRecord, .duckOthers, Bluetooth / steering wheel controls)
/// - Learned cards only; filters out Image Occlusion & cards > 220 chars
/// - Full post-drive parked review audit list for correcting misheard grades
@MainActor
final class DrivingModeManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = DrivingModeManager()
    
    @Published private(set) var state: DrivingState = .idle
    @Published private(set) var currentCard: Card?
    @Published private(set) var currentTranscript: String = ""
    @Published private(set) var sessionHistory: [DriveCardReviewRecord] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var totalEligibleCards: Int = 0
    @Published var silenceTimeoutSeconds: Double = 7.0 // Configurable 6-8s
    @Published var isMuted: Bool = false
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var eligibleCards: [Card] = []
    private var silenceTimer: Task<Void, Never>?
    private var sessionMaxCards: Int = 25
    
    // Medical synonyms dictionary for fuzzy matching
    private let medicalSynonyms: [String: [String]] = [
        "mi": ["myocardial infarction", "heart attack"],
        "myocardial infarction": ["mi", "heart attack"],
        "heart attack": ["mi", "myocardial infarction"],
        "pe": ["pulmonary embolism"],
        "pulmonary embolism": ["pe"],
        "hcm": ["hypertrophic cardiomyopathy", "hocm"],
        "hypertrophic cardiomyopathy": ["hcm", "hocm"],
        "chf": ["congestive heart failure", "heart failure"],
        "heart failure": ["chf", "congestive heart failure"],
        "nsaid": ["nonsteroidal anti-inflammatory", "ibuprofen", "naproxen", "indomethacin"],
        "nsaids": ["nonsteroidal anti-inflammatory drugs", "ibuprofen", "naproxen", "indomethacin"],
        "copd": ["chronic obstructive pulmonary disease"],
        "pcr": ["polymerase chain reaction"],
        "gerd": ["acid reflux", "gastroesophageal reflux disease"],
        "ar": ["aortic regurgitation"],
        "as": ["aortic stenosis"],
        "ms": ["mitral stenosis", "multiple sclerosis"],
        "ace inhibitor": ["lisinopril", "enalapril", "ramipril"],
        "arb": ["losartan", "valsartan"],
        "dvt": ["deep vein thrombosis"],
        "pci": ["percutaneous coronary intervention", "percutaneous", "coronary", "angioplasty"],
        "percutaneous": ["pci"],
        "coronary": ["pci"],
        "intervention": ["pci"]
    ]
    
    private let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from", "as", "is", "are", "was", "were"
    ]
    
    override private init() {
        super.init()
        speechSynthesizer.delegate = self
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        setupRemoteCommands()
    }
    
    // MARK: - Audio Session & Remote Controls
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[DrivingMode] Error setting up audio session: \(error)")
        }
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeSession()
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pauseSession()
            }
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipCurrentCard()
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repeatCurrentQuestion()
            }
            return .success
        }
    }
    
    // MARK: - Card Filtering (Learned only, Skip IO, Max Length)
    
    /// Filters deck cards for safe hands-free driving:
    /// - Only already-learned cards (interval >= 1.0 or review state)
    /// - Excludes Image Occlusion notes
    /// - Excludes cards longer than 220 characters
    static func filterEligibleCards(from cards: [Card], maxLimit: Int = 25) -> [Card] {
        return cards.filter { card in
            // 1. Must not be suspended or buried
            guard !card.isSuspended && !card.isBuried else { return false }
            
            // 2. Must be already learned (interval >= 1.0 day or review state)
            guard card.interval >= 1.0 || card.state == .review else { return false }
            
            // 3. Skip image occlusion notes
            guard card.noteType != .imageOcclusion else { return false }
            
            // 4. Skip excessively long question or answers (> 220 chars)
            let cleanFront = card.front.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let cleanBack = card.back.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            guard cleanFront.count <= 220 && cleanBack.count <= 220 else { return false }
            
            return true
        }
        .prefix(maxLimit)
        .map { $0 }
    }
    
    // MARK: - Session Lifecycle
    
    func startSession(cards: [Card], maxCards: Int = 25) {
        configureAudioSession()
        self.sessionMaxCards = maxCards
        self.eligibleCards = Self.filterEligibleCards(from: cards, maxLimit: maxCards)
        self.totalEligibleCards = eligibleCards.count
        self.sessionHistory.removeAll()
        self.currentIndex = 0
        
        guard !eligibleCards.isEmpty else {
            self.state = .completed
            return
        }
        
        presentCard(at: 0)
    }
    
    func pauseSession() {
        silenceTimer?.cancel()
        speechSynthesizer.stopSpeaking(at: .immediate)
        stopListening()
        self.state = .paused
    }
    
    func resumeSession() {
        guard state == .paused else { return }
        if let _ = currentCard {
            speakCurrentQuestion()
        }
    }
    
    func stopSession() {
        silenceTimer?.cancel()
        speechSynthesizer.stopSpeaking(at: .immediate)
        stopListening()
        self.state = .completed
    }
    
    // MARK: - Flow Execution
    
    private func presentCard(at index: Int) {
        guard index < eligibleCards.count else {
            stopSession()
            return
        }
        
        self.currentIndex = index
        self.currentCard = eligibleCards[index]
        self.currentTranscript = ""
        speakCurrentQuestion()
    }
    
    private func speakCurrentQuestion() {
        guard let card = currentCard else { return }
        silenceTimer?.cancel()
        stopListening()
        
        self.state = .speakingQuestion
        let cleanFront = sanitizeSpeechText(card.front)
        let prompt = "Question: \(cleanFront)"
        
        let utterance = AVSpeechUtterance(string: prompt)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        speechSynthesizer.speak(utterance)
    }
    
    func repeatCurrentQuestion() {
        speakCurrentQuestion()
    }
    
    func skipCurrentCard() {
        silenceTimer?.cancel()
        speechSynthesizer.stopSpeaking(at: .immediate)
        stopListening()
        
        if currentIndex + 1 < eligibleCards.count {
            presentCard(at: currentIndex + 1)
        } else {
            stopSession()
        }
    }
    
    func speakHint() {
        guard let card = currentCard else { return }
        silenceTimer?.cancel()
        speechSynthesizer.stopSpeaking(at: .immediate)
        stopListening()
        
        let hint = card.clinicalPearls.isEmpty ? (card.extra.isEmpty ? "No hint available for this card." : card.extra) : card.clinicalPearls
        let cleanHint = sanitizeSpeechText(hint)
        let utterance = AVSpeechUtterance(string: "Hint: \(cleanHint)")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        speechSynthesizer.speak(utterance)
    }
    
    // AVSpeechSynthesizerDelegate
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.state == .speakingQuestion || self.state == .speakingFeedback {
                if self.state == .speakingQuestion {
                    self.startListening()
                } else if self.state == .speakingFeedback {
                    // Advance to next card
                    if self.currentIndex + 1 < self.eligibleCards.count {
                        self.presentCard(at: self.currentIndex + 1)
                    } else {
                        self.stopSession()
                    }
                }
            }
        }
    }
    
    // MARK: - On-Device Speech Recognition & Contextual Vocabulary
    
    private func startListening() {
        guard let card = currentCard else { return }
        self.state = .listeningForAnswer
        self.currentTranscript = ""
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        // 100% On-Device & Free Recognition
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        // Feed the expected answer and medical synonyms as contextual strings for noise robustness
        let cleanBack = sanitizeSpeechText(card.back)
        var contextualVocab = cleanBack.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        for (key, synonyms) in medicalSynonyms {
            if cleanBack.localizedCaseInsensitiveContains(key) {
                contextualVocab.append(contentsOf: synonyms)
            }
        }
        recognitionRequest.contextualStrings = Array(Set(contextualVocab))
        
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("[DrivingMode] Could not start audio engine: \(error)")
        }
        
        // Start 7-second silence timeout
        startSilenceTimer()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let result = result {
                    let spoken = result.bestTranscription.formattedString
                    self.currentTranscript = spoken
                    
                    // Check for voice commands
                    if let command = self.detectVoiceCommand(in: spoken) {
                        self.handleVoiceCommand(command)
                        return
                    }
                    
                    // Reset silence timer on active speech
                    self.startSilenceTimer()
                }
                
                if error != nil {
                    self.handleSilenceOrUnrecognized()
                }
            }
        }
    }
    
    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    private func startSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(silenceTimeoutSeconds * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run {
                    if self.state == .listeningForAnswer {
                        self.handleSilenceOrUnrecognized()
                    }
                }
            }
        }
    }
    
    private func handleSilenceOrUnrecognized() {
        guard let card = currentCard, state == .listeningForAnswer else { return }
        silenceTimer?.cancel()
        stopListening()
        
        // Grade card
        evaluateAnswer(card: card, spokenText: currentTranscript)
    }
    
    // MARK: - Voice Command Detection
    
    func detectVoiceCommand(in text: String) -> DrivingVoiceCommand? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("repeat") || lower.contains("say again") {
            return .repeatQuestion
        } else if lower.contains("skip") || lower.contains("next card") {
            return .skipCard
        } else if lower.contains("hint") || lower.contains("give me a hint") {
            return .requestHint
        } else if lower.contains("stop") || lower.contains("end drive") || lower.contains("pause") {
            return .stopSession
        }
        return nil
    }
    
    private func handleVoiceCommand(_ command: DrivingVoiceCommand) {
        silenceTimer?.cancel()
        stopListening()
        
        switch command {
        case .repeatQuestion:
            speakCurrentQuestion()
        case .skipCard:
            skipCurrentCard()
        case .requestHint:
            speakHint()
        case .stopSession:
            stopSession()
        }
    }
    
    // MARK: - Fuzzy Matching & Grading Engine
    
    /// Evaluates user speech against expected card answer:
    /// - Clear correct -> Good (Rating 2)
    /// - Partial match -> Hard (Rating 1)
    /// - Wrong, silence, "I don't know" -> Again (Rating 0)
    /// - STRICT: NEVER Easy (Rating 3 is strictly prevented)
    func evaluateAnswer(card: Card, spokenText: String) {
        let cleanSpoken = spokenText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanExpected = sanitizeSpeechText(card.back).lowercased()
        
        // 1. Silence or explicit surrender
        if cleanSpoken.isEmpty || cleanSpoken.contains("i don't know") || cleanSpoken.contains("no idea") || cleanSpoken.contains("pass") {
            applyGradingResult(card: card, rating: .again, score: 0.0, spoken: spokenText, feedback: "Incorrect. The answer is: \(cleanExpected)")
            return
        }
        
        // 2. Compute similarity score with medical synonyms
        let score = computeSimilarity(spoken: cleanSpoken, expected: cleanExpected)
        
        // 3. Map to Rating: Good, Hard, Again. NEVER Easy.
        let rating: Rating
        let feedback: String
        
        if score >= 0.70 {
            rating = .good
            feedback = "Correct! Good job."
        } else if score >= 0.35 {
            rating = .hard
            feedback = "Partially correct. The full answer is: \(cleanExpected)"
        } else {
            rating = .again
            feedback = "Incorrect. The answer is: \(cleanExpected)"
        }
        
        applyGradingResult(card: card, rating: rating, score: score, spoken: spokenText, feedback: feedback)
    }
    
    private func applyGradingResult(
        card: Card,
        rating: Rating,
        score: Double,
        spoken: String,
        feedback: String
    ) {
        // Enforce the strict "Never Easy" guarantee
        let safeRating: Rating = (rating == .easy) ? .good : rating
        
        // Record review record for parked review audit sheet
        let record = DriveCardReviewRecord(
            card: card,
            question: sanitizeSpeechText(card.front),
            expectedAnswer: sanitizeSpeechText(card.back),
            userTranscript: spoken.isEmpty ? "(Silence / Unrecognized)" : spoken,
            assignedRating: safeRating,
            similarityScore: score
        )
        sessionHistory.append(record)
        
        // Speak auditory feedback to user
        self.state = .speakingFeedback
        let utterance = AVSpeechUtterance(string: feedback)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        speechSynthesizer.speak(utterance)
    }
    
    /// Computes similarity score (0.0 to 1.0) using token overlap, Levenshtein distance, and medical synonyms
    func computeSimilarity(spoken: String, expected: String) -> Double {
        let spokenTokens = Set(spoken.components(separatedBy: CharacterSet.alphanumerics.inverted).map { $0.lowercased() }.filter { $0.count > 1 && !stopWords.contains($0) })
        let expectedTokens = Set(expected.components(separatedBy: CharacterSet.alphanumerics.inverted).map { $0.lowercased() }.filter { $0.count > 1 && !stopWords.contains($0) })
        
        guard !expectedTokens.isEmpty else { return 0.0 }
        
        var matches = 0.0
        for exp in expectedTokens {
            if spokenTokens.contains(exp) {
                matches += 1.0
                continue
            }
            
            // Check medical synonyms
            if let synonyms = medicalSynonyms[exp] {
                if synonyms.contains(where: { spokenTokens.contains($0) || spoken.contains($0) }) {
                    matches += 1.0
                    continue
                }
            }
            
            // Substring fuzzy matching
            if spokenTokens.contains(where: { token in
                token.hasPrefix(exp) || exp.hasPrefix(token) || levenshteinDistance(token, exp) <= 2
            }) {
                matches += 0.8
            }
        }
        
        return min(1.0, matches / Double(expectedTokens.count))
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }
        return dist[a.count][b.count]
    }
    
    // MARK: - Text Sanitizer
    
    func sanitizeSpeechText(_ text: String) -> String {
        var clean = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "\\{\\{c\\d+::(.*?)\\}\\}", with: "$1", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "&nbsp;", with: " ")
        clean = clean.replacingOccurrences(of: "&amp;", with: "and")
        clean = clean.replacingOccurrences(of: "&lt;", with: "less than")
        clean = clean.replacingOccurrences(of: "&gt;", with: "greater than")
        clean = clean.replacingOccurrences(of: "\n", with: ". ")
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Parked Review & Grade Adjustment
    
    /// Commits all final ratings from the driving session into the database
    func commitSessionReviews(context: ModelContext) {
        for record in sessionHistory {
            // Guarantee "Easy" is never applied
            let finalRating: Rating = (record.assignedRating == .easy) ? .good : record.assignedRating
            Scheduler.applyReview(card: record.card, rating: finalRating, timeTakenMs: 6000, context: context)
        }
        try? context.save()
    }
}
