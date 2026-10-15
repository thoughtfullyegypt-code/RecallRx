import SwiftUI
import SwiftData

struct StudyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let deck: Deck
    @State private var viewModel: StudyViewModel?
    @ObservedObject private var remoteManager = BluetoothControllerManager.shared
    @State private var swipeOffset: CGSize = .zero
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
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    if let vm = viewModel {
                        VStack(spacing: 2) {
                            HStack(spacing: 5) {
                                Text(vm.deck.displayName)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                if remoteManager.isConnected {
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Image(systemName: "gamecontroller.fill")
                                            .font(.system(size: 9))
                                    }
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.12)))
                                }
                            }
                            
                            let totalSessionCards = vm.cardsStudied + vm.studyQueue.count + (vm.currentCard != nil ? 1 : 0)
                            Text("\(vm.cardsStudied) / \(max(1, totalSessionCards)) studied")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if let vm = viewModel {
                        Button {
                            vm.undoLastReview()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!vm.canUndo)
                        
                        Menu {
                            Button {
                                vm.skipCard()
                            } label: {
                                Label("Bury Card", systemImage: "moon.fill")
                            }
                            
                            Button {
                                if let current = vm.currentCard {
                                    Scheduler.suspendCard(current)
                                    try? modelContext.save()
                                    vm.nextCard()
                                }
                            } label: {
                                Label("Suspend Card", systemImage: "pause.fill")
                            }
                            
                            Divider()
                            
                            Toggle(isOn: $disableSwipeUpEasy) {
                                Label("Disable Swipe-Up Easy", systemImage: "hand.raised.slash.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                vm.showAnswer()
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.rateCard(.good)
                            }
                        }
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    
                    Button("") {
                        if vm.isShowingAnswer {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.rateCard(.again)
                            }
                        }
                    }
                    .keyboardShortcut("1", modifiers: [])
                    
                    Button("") {
                        if vm.isShowingAnswer {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.rateCard(.hard)
                            }
                        }
                    }
                    .keyboardShortcut("2", modifiers: [])
                    
                    Button("") {
                        if vm.isShowingAnswer {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.rateCard(.good)
                            }
                        }
                    }
                    .keyboardShortcut("3", modifiers: [])
                    
                    Button("") {
                        if vm.isShowingAnswer {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.rateCard(.easy)
                            }
                        }
                    }
                    .keyboardShortcut("4", modifiers: [])
                    
                    Button("") {
                        withAnimation {
                            vm.undoLastReview()
                        }
                    }
                    .keyboardShortcut("z", modifiers: [])
                    
                    Button("") {
                        withAnimation {
                            vm.skipCard()
                        }
                    }
                    .keyboardShortcut("b", modifiers: [])
                }
                .opacity(0)
                .frame(width: 0, height: 0)
            }
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                vm.showAnswer()
            }
        }
        remoteManager.onRateAgain = {
            if vm.isShowingAnswer {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.rateCard(.again)
                }
            }
        }
        remoteManager.onRateHard = {
            if vm.isShowingAnswer {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.rateCard(.hard)
                }
            }
        }
        remoteManager.onRateGood = {
            if !vm.isShowingAnswer {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    vm.showAnswer()
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.rateCard(.good)
                }
            }
        }
        remoteManager.onRateEasy = {
            if vm.isShowingAnswer {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.rateCard(.easy)
                }
            }
        }
        remoteManager.onUndo = {
            withAnimation {
                vm.undoLastReview()
            }
        }
        remoteManager.onBury = {
            withAnimation {
                vm.skipCard()
            }
        }
    }
    
    @ViewBuilder
    private func studyContent(vm: StudyViewModel, card: Card) -> some View {
        VStack(spacing: 12) {
            // Counters and Timer Bar
            HStack {
                // Remaining counts
                HStack(spacing: 8) {
                    CounterBadge(count: vm.newCount, color: .blue, title: "New")
                    CounterBadge(count: vm.learningCount, color: .orange, title: "Lrn")
                    CounterBadge(count: vm.reviewCount, color: .green, title: "Rev")
                }
                
                Spacer()
                
                // Per-card timer
                TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                    let elapsed = max(0, Int(timeline.date.timeIntervalSince(vm.cardStartTime)))
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch")
                            .font(.caption2)
                        Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.systemGray6)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            // Remote Controller HUD Indicator
            if remoteManager.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(remoteManager.controllerName):")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text(remoteManager.lastPressedButton == "None" ? "Ready" : "Last: \(remoteManager.lastPressedButton)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .transition(.opacity)
            }
            
            // Large Card Area with Interactive Swipe Grading
            GeometryReader { geometry in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Card Front
                            CardFaceView(
                                content: card.front,
                                isFront: true,
                                noteType: card.noteType,
                                card: card
                            )
                            .frame(minHeight: vm.isShowingAnswer ? 180 : geometry.size.height - 30)
                            
                            // Card Back (after reveal)
                            if vm.isShowingAnswer {
                                // Separator Divider
                                HStack {
                                    Rectangle()
                                        .fill(Color(.separator))
                                        .frame(height: 1)
                                    
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                    
                                    Rectangle()
                                        .fill(Color(.separator))
                                        .frame(height: 1)
                                }
                                .padding(.vertical, 4)
                                .transition(.opacity)
                                
                                CardFaceView(
                                    content: card.back,
                                    isFront: false,
                                    noteType: card.noteType,
                                    card: card
                                )
                                .frame(minHeight: 180)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .contentShape(Rectangle())
                    .offset(x: swipeOffset.width, y: swipeOffset.height)
                    .rotationEffect(.degrees(Double(swipeOffset.width / 20.0)))
                    .animation(.interactiveSpring(), value: swipeOffset)
                    
                    // Dynamic Swipe Grading Floating Overlay Badges
                    if vm.isShowingAnswer && (abs(swipeOffset.width) > 30 || abs(swipeOffset.height) > 30) {
                        swipeGradingBadgeOverlay
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if !vm.isShowingAnswer {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            vm.showAnswer()
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            if vm.isShowingAnswer {
                                swipeOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            if !vm.isShowingAnswer {
                                if value.translation.height < -30 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        vm.showAnswer()
                                    }
                                }
                            } else {
                                handleSwipeGradingRelease(translation: value.translation, vm: vm)
                            }
                        }
                )
            }
            
            // Bottom Action Area
            VStack(spacing: 0) {
                if !vm.isShowingAnswer {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            vm.showAnswer()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                            Text("Show Answer")
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                } else {
                    RatingButtonsView(
                        intervalStrings: vm.intervalStrings,
                        onRate: { rating in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                performRating(rating, vm: vm)
                            }
                        }
                    )
                }
                
                // Floating Undo Toast Banner
                if let msg = undoToastMessage, vm.canUndo {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            withAnimation {
                                vm.undoLastReview()
                                undoToastMessage = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Undo")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.orange))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.88))
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Color(uiColor: .systemBackground))
        }
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
        .foregroundColor(.white)
        .clipShape(Capsule())
        .shadow(color: color.opacity(0.4), radius: 10, x: 0, y: 4)
        .scaleEffect(0.8 + 0.25 * progress)
        .opacity(progress)
        .allowsHitTesting(false)
    }
    
    private func handleSwipeGradingRelease(translation: CGSize, vm: StudyViewModel) {
        let threshold: CGFloat = 80.0
        let dx = translation.width
        let dy = translation.height
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        
        if abs(dx) > abs(dy) {
            // Horizontal swipe
            if dx > threshold {
                generator.impactOccurred()
                withAnimation(.easeOut(duration: 0.2)) {
                    swipeOffset.width = 600
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    swipeOffset = .zero
                    performRating(.good, vm: vm)
                }
            } else if dx < -threshold {
                generator.impactOccurred()
                withAnimation(.easeOut(duration: 0.2)) {
                    swipeOffset.width = -600
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    swipeOffset = .zero
                    performRating(.again, vm: vm)
                }
            } else {
                withAnimation(.spring()) {
                    swipeOffset = .zero
                }
            }
        } else {
            // Vertical swipe
            if dy < -threshold {
                if disableSwipeUpEasy {
                    let lightGen = UIImpactFeedbackGenerator(style: .light)
                    lightGen.impactOccurred()
                    withAnimation(.spring()) {
                        swipeOffset = .zero
                    }
                } else {
                    generator.impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) {
                        swipeOffset.height = -600
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        swipeOffset = .zero
                        performRating(.easy, vm: vm)
                    }
                }
            } else if dy > threshold {
                generator.impactOccurred()
                withAnimation(.easeOut(duration: 0.2)) {
                    swipeOffset.height = 600
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    swipeOffset = .zero
                    performRating(.hard, vm: vm)
                }
            } else {
                withAnimation(.spring()) {
                    swipeOffset = .zero
                }
            }
        }
    }
    
    private func performRating(_ rating: Rating, vm: StudyViewModel) {
        vm.rateCard(rating)
        showUndoToast(message: "Rated \(rating.name)")
    }
    
    private func showUndoToast(message: String) {
        withAnimation {
            undoToastMessage = message
        }
        undoToastTimer?.cancel()
        undoToastTimer = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation {
                        undoToastMessage = nil
                    }
                }
            }
        }
    }
}

private struct CounterBadge: View {
    let count: Int
    let color: Color
    let title: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.bold().monospacedDigit())
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}
