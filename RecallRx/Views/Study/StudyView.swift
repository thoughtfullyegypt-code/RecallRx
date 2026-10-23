import SwiftUI
import SwiftData

struct StudyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    let deck: Deck
    @State private var viewModel: StudyViewModel?
    @ObservedObject private var remoteManager = BluetoothControllerManager.shared
    @State private var swipeOffset: CGSize = .zero
    @State private var isSwipeGradingEnabled = false
    @State private var feedbackTrigger = 0
    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("disableSwipeUpEasy") private var disableSwipeUpEasy: Bool = false
    @State private var undoToastMessage: String?
    @State private var undoToastTimer: Task<Void, Never>?
    
    init(deck: Deck, viewModel: StudyViewModel? = nil) {
        self.deck = deck
        self._viewModel = State(initialValue: viewModel)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.isComplete {
                        StudyCompleteView(
                            cardsStudied: vm.cardsStudied,
                            correctCount: vm.correctCount,
                            elapsedTime: vm.elapsedTime,
                            onDone: { dismiss() },
                            onStudyMore: {
                                Scheduler.unburyAllCards(in: vm.deck)
                                vm.buildStudyQueue()
                                vm.nextCard()
                            }
                        )
                    } else if let card = vm.currentCard {
                        studyContent(vm: vm, card: card)
                    } else {
                        // Empty deck fallback
                        StudyCompleteView(
                            cardsStudied: vm.cardsStudied,
                            correctCount: vm.correctCount,
                            elapsedTime: vm.elapsedTime,
                            onDone: { dismiss() },
                            onStudyMore: nil
                        )
                    }
                } else {
                    ProgressView("Preparing your session…")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End session", systemImage: "xmark", action: { dismiss() })
                }

                ToolbarItem(placement: .principal) {
                    Text(deck.displayName)
                        .font(.headline)
                        .lineLimit(1)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let vm = viewModel {
                        Button("Undo last review", systemImage: "arrow.uturn.backward", action: vm.undoLastReview)
                            .disabled(!vm.canUndo)

                        Menu("Study options", systemImage: "ellipsis.circle") {
                            Button("Bury card", systemImage: "moon", action: vm.skipCard)
                            Button("Suspend card", systemImage: "pause") {
                                suspendCurrentCard(vm: vm)
                            }
                            Divider()
                            Toggle("Swipe to grade", systemImage: "hand.draw", isOn: $isSwipeGradingEnabled)
                            if isSwipeGradingEnabled {
                                Toggle("Disable swipe-up Easy", systemImage: "hand.raised.slash", isOn: $disableSwipeUpEasy)
                            }
                        }
                    }
                }
            }
        }
        .background {
            if let vm = viewModel {
                Group {
                    Button("") {
                        if !vm.isShowingAnswer {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                vm.showAnswer()
                            }
                        } else {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                vm.rateCard(.good)
                            }
                        }
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    
                    Button("") {
                        if vm.isShowingAnswer {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                vm.rateCard(.again)
                            }
                        }
                    }
                    .keyboardShortcut("1", modifiers: [])
                    
                    Button("") {
                        if vm.isShowingAnswer {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                vm.rateCard(.hard)
                            }
                        }
                    }
                    .keyboardShortcut("2", modifiers: [])
                    
                    Button("") {
                        if vm.isShowingAnswer {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                vm.rateCard(.good)
                            }
                        }
                    }
                    .keyboardShortcut("3", modifiers: [])
                    
                    Button("") {
                        if vm.isShowingAnswer {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                vm.rateCard(.easy)
                            }
                        }
                    }
                    .keyboardShortcut("4", modifiers: [])
                    
                    Button("") {
                        withAnimation(reduceMotion ? nil : .default) {
                            vm.undoLastReview()
                        }
                    }
                    .keyboardShortcut("z", modifiers: [])
                    
                    Button("") {
                        withAnimation(reduceMotion ? nil : .default) {
                            vm.skipCard()
                        }
                    }
                    .keyboardShortcut("b", modifiers: [])
                }
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: feedbackTrigger)
        .onDisappear {
            undoToastTimer?.cancel()
        }
        .task {
            if viewModel == nil {
                let vm = StudyViewModel(deck: deck, modelContext: modelContext)
                viewModel = vm
                bindControllerCallbacks(vm: vm)
            } else if let vm = viewModel {
                bindControllerCallbacks(vm: vm)
            }
        }
    }
    
    private func bindControllerCallbacks(vm: StudyViewModel) {
        remoteManager.onShowAnswer = {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                vm.showAnswer()
            }
        }
        remoteManager.onRateAgain = {
            if vm.isShowingAnswer {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.rateCard(.again)
                }
            }
        }
        remoteManager.onRateHard = {
            if vm.isShowingAnswer {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.rateCard(.hard)
                }
            }
        }
        remoteManager.onRateGood = {
            if !vm.isShowingAnswer {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.showAnswer()
                }
            } else {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.rateCard(.good)
                }
            }
        }
        remoteManager.onRateEasy = {
            if vm.isShowingAnswer {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    vm.rateCard(.easy)
                }
            }
        }
        remoteManager.onUndo = {
            withAnimation(reduceMotion ? nil : .default) {
                vm.undoLastReview()
            }
        }
        remoteManager.onBury = {
            withAnimation(reduceMotion ? nil : .default) {
                vm.skipCard()
            }
        }
    }
    
    private var usesInlineActions: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    @ViewBuilder
    private func studyContent(vm: StudyViewModel, card: Card) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    StudySessionHeaderView(
                        studiedCount: vm.cardsStudied,
                        remainingCount: vm.studyQueue.count + 1,
                        newCount: vm.newCount,
                        learningCount: vm.learningCount,
                        reviewCount: vm.reviewCount,
                        cardStartTime: vm.cardStartTime,
                        showTimer: showTimer
                    )
                    .id("study-top")

                    if remoteManager.isConnected {
                        Label("Connected: \(remoteManager.controllerName)", systemImage: "gamecontroller")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .accessibilityValue(remoteManager.lastPressedButton == "None" ? "Ready" : "Last input: \(remoteManager.lastPressedButton)")
                    }

                    VStack(spacing: 20) {
                        CardFaceView(content: card.front, isFront: true, noteType: card.noteType, card: card)
                            .id("question-\(card.id)")
                        if vm.isShowingAnswer {
                            CardFaceView(content: card.back, isFront: false, noteType: card.noteType, card: card)
                                .id("answer-\(card.id)")
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .offset(x: reduceMotion ? 0 : swipeOffset.width, y: reduceMotion ? 0 : swipeOffset.height)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(swipeOffset.width / 30)))
                    .overlay {
                        if isSwipeGradingEnabled && vm.isShowingAnswer {
                            swipeGradingBadgeOverlay
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 30)
                            .onChanged { value in
                                if vm.isShowingAnswer {
                                    swipeOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                if vm.isShowingAnswer {
                                    handleSwipeGradingRelease(translation: value.translation, vm: vm)
                                } else if value.translation.height < -30 {
                                    revealAnswer(vm: vm)
                                }
                            },
                        including: isSwipeGradingEnabled ? .all : .none
                    )
                    .accessibilityAction(named: "Show answer") {
                        revealAnswer(vm: vm)
                    }

                    if usesInlineActions {
                        studyActions(vm: vm)
                    }
                }
                .frame(maxWidth: AppTheme.contentWidth)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: vm.isShowingAnswer) { _, isShowingAnswer in
                if isShowingAnswer {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        proxy.scrollTo("answer-\(card.id)", anchor: .top)
                    }
                }
            }
            .onChange(of: card.id) {
                proxy.scrollTo("study-top", anchor: .top)
            }
        }
        .background(AppTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !usesInlineActions {
                studyActions(vm: vm)
                    .background(.bar)
            }
        }
    }

    private func studyActions(vm: StudyViewModel) -> some View {
        StudyActionsView(
            isShowingAnswer: vm.isShowingAnswer,
            intervalStrings: vm.intervalStrings,
            undoMessage: vm.canUndo ? undoToastMessage : nil,
            swipeGradingEnabled: isSwipeGradingEnabled,
            disableSwipeUpEasy: disableSwipeUpEasy,
            onShowAnswer: { revealAnswer(vm: vm) },
            onRate: { rating in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    performRating(rating, vm: vm)
                }
            },
            onUndo: {
                vm.undoLastReview()
                undoToastMessage = nil
            }
        )
    }

    private func revealAnswer(vm: StudyViewModel) {
        guard !vm.isShowingAnswer else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            vm.showAnswer()
        }
    }

    private func suspendCurrentCard(vm: StudyViewModel) {
        guard let card = vm.currentCard else { return }
        Scheduler.suspendCard(card)
        try? modelContext.save()
        vm.nextCard()
    }

    // MARK: - Swipe Grading Overlays & Gestures
    
    @ViewBuilder
    private var swipeGradingBadgeOverlay: some View {
        let dx = swipeOffset.width
        let dy = swipeOffset.height
        
        if abs(dx) > abs(dy) {
            // Horizontal: Left = Again, Right = Good
            if dx > 0 {
                swipeBadgeView(title: "GOOD", icon: "hand.thumbsup.fill", color: .green, offset: dx)
            } else {
                swipeBadgeView(title: "AGAIN", icon: "arrow.counterclockwise", color: .red, offset: dx)
            }
        } else {
            // Vertical: Up = Easy, Down = Hard
            if dy < 0 {
                if disableSwipeUpEasy {
                    swipeBadgeView(title: "SWIPE UP DISABLED", icon: "hand.raised.slash.fill", color: .gray, offset: dy)
                } else {
                    swipeBadgeView(title: "EASY", icon: "sparkles", color: .blue, offset: dy)
                }
            } else {
                swipeBadgeView(title: "HARD", icon: "exclamationmark.triangle.fill", color: .orange, offset: dy)
            }
        }
    }
    
    private func swipeBadgeView(title: String, icon: String, color: Color, offset: CGFloat) -> some View {
        let progress = min(1.0, max(0.0, (abs(offset) - 30.0) / 70.0))
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2.bold())
            Text(title)
                .font(.title2.bold())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(color.opacity(0.85 + 0.15 * progress))
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: color.opacity(0.4), radius: 10, x: 0, y: 4)
        .scaleEffect(reduceMotion ? 1 : 0.8 + 0.25 * progress)
        .opacity(progress)
        .allowsHitTesting(false)
    }
    
    private func handleSwipeGradingRelease(translation: CGSize, vm: StudyViewModel) {
        let threshold: CGFloat = 80
        let dx = translation.width
        let dy = translation.height
        let rating: Rating?

        if abs(dx) > abs(dy) {
            rating = dx > threshold ? .good : (dx < -threshold ? .again : nil)
        } else if dy < -threshold && !disableSwipeUpEasy {
            rating = .easy
        } else if dy > threshold {
            rating = .hard
        } else {
            rating = nil
        }

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            swipeOffset = .zero
            if let rating {
                feedbackTrigger += 1
                performRating(rating, vm: vm)
            }
        }
    }

    private func performRating(_ rating: Rating, vm: StudyViewModel) {
        vm.rateCard(rating)
        showUndoToast(message: "Rated \(rating.name)")
    }
    
    private func showUndoToast(message: String) {
        withAnimation(reduceMotion ? nil : .default) {
            undoToastMessage = message
        }
        undoToastTimer?.cancel()
        undoToastTimer = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(reduceMotion ? nil : .default) {
                        undoToastMessage = nil
                    }
                }
            }
        }
    }
}
