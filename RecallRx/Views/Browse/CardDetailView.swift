import SwiftUI
import SwiftData

struct CardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var card: Card

    @State private var isShowingEditor: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var showRescheduleSheet: Bool = false
    @State private var rescheduledDate: Date = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Card Display (Front & Back)
                cardContentCard

                // Card Metadata
                cardInfoSection

                // Tags Section
                if !card.tags.isEmpty {
                    tagsSection
                }

                // Review History
                reviewHistorySection

                // Destructive Actions
                actionButtonsSection
            }
            .padding()
            .frame(maxWidth: AppTheme.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.canvas)
        .navigationTitle("Card Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit Card", systemImage: "pencil") { isShowingEditor = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Card options", systemImage: "ellipsis.circle") {
                    Button {
                        isShowingEditor = true
                    } label: {
                        Label("Edit Card", systemImage: "pencil")
                    }

                    Button {
                        toggleSuspension()
                    } label: {
                        Label(
                            card.isSuspended ? "Unsuspend Card" : "Suspend Card",
                            systemImage: card.isSuspended ? "play.circle" : "pause.circle"
                        )
                    }

                    Button {
                        rescheduledDate = card.dueDate
                        showRescheduleSheet = true
                    } label: {
                        Label("Reschedule...", systemImage: "calendar.badge.clock")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Card", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            CardEditorView(card: card)
        }
        .sheet(isPresented: $showRescheduleSheet) {
            rescheduleSheetView
        }
        .alert("Delete Card", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteCard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this card? This action cannot be undone.")
        }
    }

    // MARK: - Card Display Box

    private var cardContentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Front
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Question")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            badge(text: card.state.displayName, color: stateBadgeColor(card.state))
                            if card.isSuspended {
                                badge(text: "Suspended", color: .orange)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            badge(text: card.state.displayName, color: stateBadgeColor(card.state))
                            if card.isSuspended {
                                badge(text: "Suspended", color: .orange)
                            }
                        }
                    }
                }

                RichTextHTMLView(
                    rawContent: card.front.isEmpty ? "No prompt text" : card.front,
                    isFront: false,
                    noteType: card.noteType
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }

            Divider()

            // Back
            VStack(alignment: .leading, spacing: 6) {
                Text("Answer")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                RichTextHTMLView(
                    rawContent: card.back.isEmpty ? "No answer text" : card.back,
                    isFront: false,
                    noteType: card.noteType
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            
            // High-Yield Medical Resources
            if card.hasMedicalResources {
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "cross.case.fill")
                            .foregroundStyle(.blue)
                        Text("High-Yield Medical References")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    
                    if !card.extra.isEmpty {
                        medicalInfoBox(title: "Extra", icon: "doc.text.fill", color: .indigo, text: card.extra)
                    }
                    if !card.firstAid.isEmpty {
                        medicalInfoBox(title: "Outline", icon: "cross.fill", color: .blue, text: card.firstAid)
                    }
                    if !card.sketchy.isEmpty {
                        medicalInfoBox(title: "Visual", icon: "paintpalette.fill", color: .orange, text: card.sketchy)
                    }
                    if !card.pathoma.isEmpty {
                        medicalInfoBox(title: "Pathology", icon: "microscope.fill", color: .purple, text: card.pathoma)
                    }
                    if !card.clinicalPearls.isEmpty {
                        medicalInfoBox(title: "Clinical Pearls", icon: "lightbulb.fill", color: .orange, text: card.clinicalPearls)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(.rect(cornerRadius: AppTheme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: AppTheme.cornerRadius).strokeBorder(AppTheme.border) }
    }
    
    private func medicalInfoBox(title: String, icon: String, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Card Info Section

    private var cardInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Card Statistics & Info")
                .font(.headline)

            VStack(spacing: 0) {
                infoRow(label: "Deck", value: card.deck?.name ?? "None", icon: "folder.fill")
                Divider()
                infoRow(label: "Note Type", value: card.noteType.displayName, icon: card.noteType.iconName)
                Divider()
                infoRow(label: "State", value: card.state.displayName, icon: "circle.circle.fill")
                Divider()
                infoRow(label: "Due Date", value: "\(card.dueDate.shortDescription) (\(card.dueDate.relativeDescription))", icon: "calendar")
                Divider()
                infoRow(label: "Interval", value: formatInterval(card.interval), icon: "arrow.triangle.2.circlepath")
                Divider()
                infoRow(label: "Ease Factor", value: String(format: "%.0f%%", card.easeFactor * 100.0), icon: "chart.line.uptrend.xyaxis")
                Divider()
                infoRow(label: "Total Reviews", value: "\(card.repetitions)", icon: "repeat")
                Divider()
                infoRow(label: "Lapses", value: "\(card.lapseCount)", icon: "exclamationmark.arrow.circlepath")
                if card.fsrsStability > 0 {
                    Divider()
                    infoRow(label: "FSRS Retrievability", value: String(format: "%.1f%%", card.retrievability() * 100.0), icon: "brain.head.profile")
                    Divider()
                    infoRow(label: "FSRS Stability", value: String(format: "%.1f days", card.fsrsStability), icon: "shield.fill")
                    Divider()
                    infoRow(label: "FSRS Difficulty", value: card.fsrsDifficultyDescription, icon: "gauge.medium")
                }
                Divider()
                infoRow(label: "Created", value: card.createdAt.shortDescription, icon: "calendar.badge.plus")
                Divider()
                infoRow(label: "Last Modified", value: card.modifiedAt.shortDescription, icon: "clock")
            }
            .padding(.horizontal, 14)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        LabeledContent {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(card.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.footnote)
                            Text(tag)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.accent.opacity(0.12))
                        .foregroundStyle(AppTheme.accent)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Review History Section

    private var reviewHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Review History")
                    .font(.headline)

                Spacer()

                Text("\(card.reviewLogs.count) reviews")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if card.reviewLogs.isEmpty {
                ContentUnavailableView(
                    "No reviews yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Study this card to start its review history.")
                )
                .background(AppTheme.surface, in: .rect(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedReviewLogs, id: \.id) { log in
                        reviewLogRow(log: log)
                    }
                }
            }
        }
    }

    private var sortedReviewLogs: [ReviewLog] {
        card.reviewLogs.sorted { $0.reviewDate > $1.reviewDate }
    }

    private func reviewLogRow(log: ReviewLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(log.reviewDate.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.bold())
            Label(log.ratingName, systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(ratingColor(log.rating))
            Text("Interval: \(Int(log.intervalBefore))d → \(Int(log.intervalAfter))d")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Ease: \(Int(log.easeFactorBefore * 100))% → \(Int(log.easeFactorAfter * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Response time: \(Double(log.timeTakenMs) / 1000, format: .number.precision(.fractionLength(1))) seconds")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions Section

    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            Button {
                toggleSuspension()
            } label: {
                HStack {
                    Spacer()
                    Label(
                        card.isSuspended ? "Unsuspend Card" : "Suspend Card",
                        systemImage: card.isSuspended ? "play.circle.fill" : "pause.circle.fill"
                    )
                    .fontWeight(.medium)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.12))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                rescheduledDate = card.dueDate
                showRescheduleSheet = true
            } label: {
                HStack {
                    Spacer()
                    Label("Reschedule Card", systemImage: "calendar.badge.clock")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.12))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Delete Card", systemImage: "trash.fill")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Reschedule Sheet

    private var rescheduleSheetView: some View {
        NavigationStack {
            Form {
                Section("Select Due Date") {
                    DatePicker("Due Date", selection: $rescheduledDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                }

                Section {
                    Button("Due Today") {
                        rescheduledDate = .now
                    }
                    Button("Due Tomorrow") {
                        rescheduledDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                    }
                    Button("Due in 1 Week") {
                        rescheduledDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
                    }
                }
            }
            .navigationTitle("Reschedule Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRescheduleSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyReschedule()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Helpers

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func stateBadgeColor(_ state: CardState) -> Color {
        switch state {
        case .new: return .blue
        case .learning: return .orange
        case .review: return .green
        case .relearning: return .red
        }
    }

    private func ratingColor(_ rating: Int) -> Color {
        switch rating {
        case 0: return .red
        case 1: return .orange
        case 2: return .green
        case 3: return .blue
        default: return .secondary
        }
    }

    private func formatInterval(_ days: Double) -> String {
        if days < 1.0 {
            return "< 1 day"
        } else if days == 1.0 {
            return "1 day"
        } else {
            return "\(Int(days)) days"
        }
    }

    private func toggleSuspension() {
        if card.isSuspended {
            Scheduler.unsuspendCard(card)
        } else {
            Scheduler.suspendCard(card)
        }
        try? modelContext.save()
    }

    private func applyReschedule() {
        card.dueDate = rescheduledDate
        card.modifiedAt = .now
        try? modelContext.save()
        showRescheduleSheet = false
    }

    private func deleteCard() {
        modelContext.delete(card)
        try? modelContext.save()
        dismiss()
    }
}
