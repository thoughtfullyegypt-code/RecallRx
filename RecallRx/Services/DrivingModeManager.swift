import Foundation
import Combine
import AVFoundation
import Speech
import MediaPlayer
import SwiftData

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
    @Published private(set) var permissionMessage: String = ""
    private var tapInstalled = false
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var eligibleCards: [Card] = []
    private var silenceTimer: Task<Void, Never>?
    private var sessionMaxCards: Int = 25
    
    override private init() {
        super.init()
        speechSynthesizer.delegate = self
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        setupRemoteCommands()
    }
    
    private static func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else { return false }
        return await AVAudioApplication.requestRecordPermission()
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
        cards.filter { card in
            guard !card.isSuspended, !card.isBuried,
                  card.interval >= 1.0 || card.state == .review else { return false }
            return audioContent(for: card) != nil
        }
        .prefix(max(0, maxLimit))
        .map { $0 }
    }

    static func audioContent(for card: Card) -> AudioStudyContent? {
        AudioStudyContent.make(front: card.front, back: card.back, noteType: card.noteType)
    }

    var currentQuestion: String {
        guard let currentCard else { return "" }
        return Self.audioContent(for: currentCard)?.question ?? "This card needs visual review."
    }

    // MARK: - Session Lifecycle
    
    func startSession(cards: [Card], maxCards: Int = 25) {
        self.sessionMaxCards = maxCards
        self.eligibleCards = Self.filterEligibleCards(from: cards, maxLimit: maxCards)
        self.totalEligibleCards = eligibleCards.count
        self.sessionHistory.removeAll()
        self.currentIndex = 0
        self.permissionMessage = ""
        self.currentCard = nil

        guard !eligibleCards.isEmpty else {
            self.permissionMessage = "No audio-ready learned cards. Short text questions need a spoken answer; visual notes, malformed blanks, and unanswered cards are skipped."
            self.state = .completed
            return
        }

        Task {
            let allowed = await Self.requestPermissions()
            if !allowed {
                self.permissionMessage = "Microphone and speech recognition are required. They stay on this iPhone."
                self.state = .completed
                return
            }
            self.configureAudioSession()
            self.presentCard(at: 0)
        }
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
        self.currentCard = nil
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
        guard let content = Self.audioContent(for: card) else {
            skipCurrentCard()
            return
        }
        silenceTimer?.cancel()
        speechSynthesizer.stopSpeaking(at: .immediate)
        stopListening()

        self.state = .speakingQuestion
        let prompt = "Question: \(content.question)"
        
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
        
        guard let content = Self.audioContent(for: card) else {
            skipCurrentCard()
            return
        }
        let hint = content.isCloze
            ? "Say the missing term for each blank."
            : (card.clinicalPearls.isEmpty ? (card.extra.isEmpty ? "No hint available for this card." : card.extra) : card.clinicalPearls)
        let cleanHint = sanitizeSpeechText(hint)
        self.state = .speakingQuestion
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
        guard let content = Self.audioContent(for: card) else {
            skipCurrentCard()
            return
        }
        guard speechRecognizer?.supportsOnDeviceRecognition == true else {
            permissionMessage = "On-device speech recognition is unavailable on this device. Audio review was stopped without grading this card."
            stopSession()
            return
        }
        self.state = .listeningForAnswer
        self.currentTranscript = ""
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.contextualStrings = AudioStudyAnswerEvaluator.contextualVocabulary(for: content.expectedAnswers)

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        if tapInstalled {
            node.removeTap(onBus: 0)
            tapInstalled = false
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        tapInstalled = true
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            permissionMessage = "Audio recording could not start. This card was not graded."
            stopSession()
            return
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
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
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
        AudioStudyAnswerEvaluator.voiceCommand(in: text)
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
        guard let content = Self.audioContent(for: card) else {
            permissionMessage = "This note needs visual review and was not graded."
            if currentCard?.id == card.id { skipCurrentCard() }
            return
        }
        let result = AudioStudyAnswerEvaluator.evaluate(spoken: spokenText, expectedAnswers: content.expectedAnswers)
        let rating = Rating(rawValue: result.rating) ?? .again
        let feedback: String
        switch rating {
        case .good:
            feedback = "Correct! Good job."
        case .hard:
            feedback = "Partially correct. The full answer is: \(content.expectedAnswer)"
        case .again, .easy:
            feedback = "Incorrect. The answer is: \(content.expectedAnswer)"
        }
        applyGradingResult(card: card, content: content, rating: rating, score: result.similarity, spoken: spokenText, feedback: feedback)
    }

    private func applyGradingResult(
        card: Card,
        content: AudioStudyContent,
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
            question: content.question,
            expectedAnswer: content.expectedAnswer,
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
    
    func computeSimilarity(spoken: String, expected: String) -> Double {
        AudioStudyAnswerEvaluator.similarity(spoken: spoken, expected: expected)
    }

    // MARK: - Text Sanitizer
    
    func sanitizeSpeechText(_ text: String) -> String {
        AudioStudyContent.sanitize(text)
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
