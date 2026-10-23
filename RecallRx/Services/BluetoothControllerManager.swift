import Foundation
import SwiftUI
import GameController

/// Native Bluetooth Remote & Game Controller Integration Engine
/// Enables hands-free studying with 8BitDo Micro, 8BitDo Zero 2, Joy-Cons, Xbox, and PlayStation controllers.
@MainActor
final class BluetoothControllerManager: ObservableObject {
    static let shared = BluetoothControllerManager(defaults: AppRuntime.defaults())
    
    // MARK: - Published State
    @Published var isConnected: Bool = false
    @Published var controllerName: String = "No Controller"
    @Published var lastPressedButton: String = "None"
    @Published var lastPressTime: Date = .distantPast
    
    // MARK: - Custom Button Mappings (Configurable in Settings)
    @AppStorage("remoteButtonAAction") var buttonAAction: String = "good"      // or "showAnswer"
    @AppStorage("remoteButtonBAction") var buttonBAction: String = "again"
    @AppStorage("remoteButtonXAction") var buttonXAction: String = "hard"
    @AppStorage("remoteButtonYAction") var buttonYAction: String = "easy"
    @AppStorage("remoteDpadDownAction") var dpadDownAction: String = "showAnswer"
    @AppStorage("remoteL1Action") var l1Action: String = "undo"
    @AppStorage("remoteR1Action") var r1Action: String = "bury"
    
    // MARK: - Active Review Callbacks
    var onShowAnswer: (() -> Void)?
    var onRateAgain: (() -> Void)?
    var onRateHard: (() -> Void)?
    var onRateGood: (() -> Void)?
    var onRateEasy: (() -> Void)?
    var onUndo: (() -> Void)?
    var onBury: (() -> Void)?
    
    init(defaults: UserDefaults = .standard, observesControllers: Bool = true) {
        _buttonAAction = AppStorage(wrappedValue: "good", "remoteButtonAAction", store: defaults)
        _buttonBAction = AppStorage(wrappedValue: "again", "remoteButtonBAction", store: defaults)
        _buttonXAction = AppStorage(wrappedValue: "hard", "remoteButtonXAction", store: defaults)
        _buttonYAction = AppStorage(wrappedValue: "easy", "remoteButtonYAction", store: defaults)
        _dpadDownAction = AppStorage(wrappedValue: "showAnswer", "remoteDpadDownAction", store: defaults)
        _l1Action = AppStorage(wrappedValue: "undo", "remoteL1Action", store: defaults)
        _r1Action = AppStorage(wrappedValue: "bury", "remoteR1Action", store: defaults)
        if observesControllers && !AppRuntime.isTesting {
            setupControllerObservers()
            checkForConnectedControllers()
        }
    }
    
    // MARK: - Observer Setup
    private func setupControllerObservers() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, let controller = notification.object as? GCController else { return }
                self.configureController(controller)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForConnectedControllers()
            }
        }
    }
    
    func checkForConnectedControllers() {
        let controllers = GCController.controllers()
        if let first = controllers.first {
            configureController(first)
        } else if !isSimulated {
            isConnected = false
            controllerName = "No Controller"
        }
    }
    
    private var isSimulated: Bool = false
    
    func simulateConnection(name: String = "8BitDo Micro (Bluetooth)") {
        isSimulated = true
        isConnected = true
        controllerName = name
    }
    
    func simulateDisconnection() {
        isSimulated = false
        checkForConnectedControllers()
    }
    
    private func configureController(_ controller: GCController) {
        isConnected = true
        controllerName = controller.vendorName ?? "Bluetooth Remote"
        
        // 1. Extended Gamepad (8BitDo Micro in D-mode/X-mode, Xbox, PS, Switch Joy-Con)
        if let extended = controller.extendedGamepad {
            extended.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "Button A", actionKey: self?.buttonAAction ?? "good")
            }
            
            extended.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "Button B", actionKey: self?.buttonBAction ?? "again")
            }
            
            extended.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "Button X", actionKey: self?.buttonXAction ?? "hard")
            }
            
            extended.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "Button Y", actionKey: self?.buttonYAction ?? "easy")
            }
            
            extended.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "D-Pad Down", actionKey: self?.dpadDownAction ?? "showAnswer")
            }
            
            extended.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "D-Pad Left", actionKey: "again")
            }
            
            extended.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "D-Pad Up", actionKey: "hard")
            }
            
            extended.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "D-Pad Right", actionKey: "good")
            }
            
            extended.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "L1 / Shoulder", actionKey: self?.l1Action ?? "undo")
            }
            
            extended.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "R1 / Shoulder", actionKey: self?.r1Action ?? "bury")
            }
        }
        
        // 2. Micro Gamepad (8BitDo Zero 2 in Gamepad mode)
        else if let micro = controller.microGamepad {
            micro.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "A", actionKey: self?.buttonAAction ?? "good")
            }
            micro.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "X", actionKey: self?.buttonXAction ?? "again")
            }
            micro.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.handleButtonPress(name: "D-Pad Down", actionKey: "showAnswer")
            }
        }
    }
    
    // MARK: - Action Dispatch
    func handleButtonPress(name: String, actionKey: String) {
        lastPressedButton = name
        lastPressTime = Date()
        
        switch actionKey {
        case "showAnswer":
            onShowAnswer?()
        case "again":
            onRateAgain?()
        case "hard":
            onRateHard?()
        case "good":
            onRateGood?()
        case "easy":
            onRateEasy?()
        case "undo":
            onUndo?()
        case "bury":
            onBury?()
        default:
            break
        }
    }
    
    // MARK: - Hardware Keyboard Key Command Handler (For 8BitDo in K-Mode)
    func handleKeyCommand(_ key: String, isShowingAnswer: Bool) {
        switch key.lowercased() {
        case " ", "\r", "space":
            if !isShowingAnswer {
                handleButtonPress(name: "Space (Show Answer)", actionKey: "showAnswer")
            } else {
                handleButtonPress(name: "Space (Good)", actionKey: "good")
            }
        case "1":
            handleButtonPress(name: "1 (Again)", actionKey: "again")
        case "2":
            handleButtonPress(name: "2 (Hard)", actionKey: "hard")
        case "3":
            handleButtonPress(name: "3 (Good)", actionKey: "good")
        case "4":
            handleButtonPress(name: "4 (Easy)", actionKey: "easy")
        case "z", "u":
            handleButtonPress(name: "Z (Undo)", actionKey: "undo")
        case "b":
            handleButtonPress(name: "B (Bury)", actionKey: "bury")
        default:
            break
        }
    }
}
