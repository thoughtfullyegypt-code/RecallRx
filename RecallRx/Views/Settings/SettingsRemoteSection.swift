import SwiftUI

struct SettingsRemoteSection: View {
    @ObservedObject private var remoteManager = BluetoothControllerManager.shared

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(remoteManager.controllerName)
                    Text(remoteManager.isConnected ? "Connected · Ready for hands-free study" : "No device connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(AppTheme.accent)
            }
            .accessibilityElement(children: .combine)

            NavigationLink {
                RemoteButtonMappingView()
            } label: {
                Label("Customize Remote Buttons", systemImage: "slider.horizontal.3")
            }

            DisclosureGroup("Remote Input Diagnostics") {
                LabeledContent("Last Pressed", value: remoteManager.lastPressedButton)
                    .font(.subheadline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))]) {
                    Button("Test Button A") {
                        remoteManager.handleButtonPress(name: "Button A", actionKey: remoteManager.buttonAAction)
                    }
                    .frame(minHeight: 44)
                    Button("Test Button B") {
                        remoteManager.handleButtonPress(name: "Button B", actionKey: remoteManager.buttonBAction)
                    }
                    .frame(minHeight: 44)
                    Button("Test Button X") {
                        remoteManager.handleButtonPress(name: "Button X", actionKey: remoteManager.buttonXAction)
                    }
                    .frame(minHeight: 44)
                    Button("Test Button Y") {
                        remoteManager.handleButtonPress(name: "Button Y", actionKey: remoteManager.buttonYAction)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    if remoteManager.isConnected {
                        remoteManager.simulateDisconnection()
                    } else {
                        remoteManager.simulateConnection(name: "8BitDo Micro (Bluetooth)")
                    }
                } label: {
                    Label(
                        remoteManager.isConnected ? "Simulate Disconnection" : "Simulate 8BitDo Connection",
                        systemImage: remoteManager.isConnected ? "bolt.slash" : "bolt.fill"
                    )
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text("Bluetooth Remote & Gamepads")
        } footer: {
            Text("Compatible with 8BitDo Micro, 8BitDo Zero 2, Joy-Cons, Xbox, and PS controllers. On 8BitDo Micro, use D-mode (D+Home) for gamepad input or K-mode for keyboard shortcuts.")
        }
    }
}
