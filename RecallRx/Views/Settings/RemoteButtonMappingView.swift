import SwiftUI

// MARK: - Remote Button Customization View

struct RemoteButtonMappingView: View {
    @AppStorage("remoteButtonAAction") var buttonAAction: String = "good"
    @AppStorage("remoteButtonBAction") var buttonBAction: String = "again"
    @AppStorage("remoteButtonXAction") var buttonXAction: String = "hard"
    @AppStorage("remoteButtonYAction") var buttonYAction: String = "easy"
    @AppStorage("remoteDpadDownAction") var dpadDownAction: String = "showAnswer"
    @AppStorage("remoteL1Action") var l1Action: String = "undo"
    @AppStorage("remoteR1Action") var r1Action: String = "bury"

    let options = [
        ("showAnswer", "Show Answer"),
        ("again", "Again (Rating 1)"),
        ("hard", "Hard (Rating 2)"),
        ("good", "Good (Rating 3)"),
        ("easy", "Easy (Rating 4)"),
        ("undo", "Undo Last Review"),
        ("bury", "Bury Card")
    ]

    var body: some View {
        Form {
            Section("Face Buttons (8BitDo / Gamepad)") {
                picker(title: "Button A", selection: $buttonAAction)
                picker(title: "Button B", selection: $buttonBAction)
                picker(title: "Button X", selection: $buttonXAction)
                picker(title: "Button Y", selection: $buttonYAction)
            }

            Section("D-Pad & Shoulder Bumpers") {
                picker(title: "D-Pad Down", selection: $dpadDownAction)
                picker(title: "L1 / Left Shoulder", selection: $l1Action)
                picker(title: "R1 / Right Shoulder", selection: $r1Action)
            }

            Section("Keyboard Mode (K-Mode) Shortcuts") {
                HStack {
                    Text("Space")
                    Spacer()
                    Text("Show Answer / Good")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("1")
                    Spacer()
                    Text("Again")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("2")
                    Spacer()
                    Text("Hard")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("3")
                    Spacer()
                    Text("Good")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("4")
                    Spacer()
                    Text("Easy")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Z")
                    Spacer()
                    Text("Undo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvas)
        .navigationTitle("Button Mappings")
    }

    private func picker(title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.0) { opt in
                Text(opt.1).tag(opt.0)
            }
        }
    }
}
