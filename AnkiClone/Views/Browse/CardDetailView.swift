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
        }
        .navigationTitle(card.front.truncated50.isEmpty ? "Card Details" : card.front.truncated50)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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
                } label: {
                    Image(systemName: "ellipsis.circle")
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
                HStack {
                    Text("FRONT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Spacer()

                    badge(text: card.state.displayName, color: stateBadgeColor(card.state))
                    if card.isSuspended {
                        badge(text: "Suspended", color: .yellow)
                    }
                }

                Text(card.front.isEmpty ? "No prompt text" : card.front)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Back
            VStack(alignment: .leading, spacing: 6) {
                Text("BACK")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(card.back.isEmpty ? "No answer text" : card.back)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // High-Yield Medical Resources
            if card.hasMedicalResources {
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "cross.case.fill")
                            .foregroundColor(.blue)
                        Text("High-Yield Medical References")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                    
                    if !card.extra.isEmpty {
                        medicalInfoBox(title: "Extra", icon: "doc.text.fill", color: .indigo, text: card.extra)
                    }
                    if !card.firstAid.isEmpty {
                        medicalInfoBox(title: "First Aid", icon: "cross.fill", color: .blue, text: card.firstAid)
                    }
                    if !card.sketchy.isEmpty {
                        medicalInfoBox(title: "Sketchy / Pixorize", icon: "paintpalette.fill", color: .orange, text: card.sketchy)
                    }
                    if !card.pathoma.isEmpty {
                        medicalInfoBox(title: "Pathoma", icon: "microscope.fill", color: .purple, text: card.pathoma)
                    }
                    if !card.clinicalPearls.isEmpty {
                        medicalInfoBox(title: "Clinical Pearls", icon: "lightbulb.fill", color: .yellow, text: card.clinicalPearls)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
    
    private func medicalInfoBox(title: String, icon: String, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)
            Text(text)
                .font(.footnote)
                .foregroundColor(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(8)
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
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
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
                                .font(.caption2)
                            Text(tag)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
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
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No reviews recorded yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
        HStack(spacing: 12) {
            // Rating Badge
            Text(log.ratingName)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ratingColor(log.rating).opacity(0.15))
                .foregroundStyle(ratingColor(log.rating))
                .clipShape(Capsule())

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(log.reviewDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Interval: \(Int(log.intervalBefore))d → \(Int(log.intervalAfter))d  •  Ease: \(Int(log.easeFactorBefore * 100))% → \(Int(log.easeFactorAfter * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Time taken
            Text(String(format: "%.1fs", Double(log.timeTakenMs) / 1000.0))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            .font(.caption2.bold())
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
