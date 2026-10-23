import SwiftUI

struct CardDraftPreview: View {
    let viewModel: CardEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Question", systemImage: "questionmark.circle")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accent)
            Text(viewModel.selectedNoteType == .cloze
                 ? viewModel.clozeQuestionPreview
                 : (viewModel.front.isEmpty ? "Your question will appear here." : viewModel.front))
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Label("Answer", systemImage: "checkmark.circle")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accent)
            Text(viewModel.selectedNoteType == .cloze
                 ? viewModel.clozeAnswerPreview
                 : (viewModel.back.isEmpty ? "Your answer will appear here." : viewModel.back))
                .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.selectedNoteType == .cloze && !viewModel.back.isEmpty {
                Text(viewModel.back)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .textSelection(.enabled)
    }
}
