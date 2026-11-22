import AppKit
import Carbon

struct LaunchShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let value = event.charactersIgnoringModifiers, value.count == 1,
              let scalar = value.unicodeScalars.first, scalar.value >= 32, scalar.value <= 126 else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = modifiers
        self.key = value == " " ? "空格" : value.uppercased()
    }
}

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    /// 双击 shift：唤出/隐藏面板
    var onHotkey: (() -> Void)?
    /// 4次 shift：切换收藏夹
    var onQuadShift: (() -> Void)?
    @Published private(set) var shortcut: LaunchShortcut?
    @Published private(set) var registrationFailed = false
    @Published private(set) var isRecording = false
    var recordingHandler: ((NSEvent) -> Void)?
    private var carbonHotkey: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?
    private var nextCarbonID: UInt32 = 0
    private var activeCarbonID: UInt32?
    static let carbonSignature: OSType = 0x4F435450
    var shortcutLabel: String { shortcut?.label ?? "连按两次 Shift" }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var shiftKeyDown = false
    private var otherKeyPressed = false

    private var shiftTapCount = 0
    private var tapTimer: DispatchWorkItem?
    /// 连续两次 shift 之间的最大间隔
    private let tapWindow: TimeInterval = 0.4

    private init() {}

    func register() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                                           nil, &id)
            guard status == noErr, id.signature == HotkeyManager.carbonSignature,
                  id.id == HotkeyManager.shared.activeCarbonID else { return OSStatus(eventNotHandledErr) }
            let hotkeys = HotkeyManager.shared
            if !hotkeys.isRecording { hotkeys.onHotkey?() }
            return noErr
        }, 1, &type, nil, &carbonHandler)

        if let data = UserDefaults.standard.data(forKey: SettingsKey.launchShortcut),
           let stored = try? JSONDecoder().decode(LaunchShortcut.self, from: data) {
            registrationFailed = !setShortcut(stored, save: false)
        }
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.handleEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

    }

    func unregister() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let carbonHotkey { UnregisterEventHotKey(carbonHotkey) }
        if let carbonHandler { RemoveEventHandler(carbonHandler) }
        carbonHotkey = nil
        carbonHandler = nil
        activeCarbonID = nil
        resetTaps()
    }

    func beginRecording(_ handler: @escaping (NSEvent) -> Void) {
        resetTaps()
        shiftKeyDown = false
        recordingHandler = handler
        isRecording = true
    }

    func stopRecording() {
        recordingHandler = nil
        isRecording = false
    }

    @discardableResult
    func setShortcut(_ value: LaunchShortcut?, save: Bool = true) -> Bool {
        if let value, value.keyCode == shortcut?.keyCode, value.modifiers == shortcut?.modifiers { return true }
        var replacement: EventHotKeyRef?
        if let value {
            guard carbonHandler != nil else { return false }
            nextCarbonID &+= 1
            let id = EventHotKeyID(signature: Self.carbonSignature, id: nextCarbonID)
            guard RegisterEventHotKey(value.keyCode, value.modifiers, id, GetApplicationEventTarget(), 0,
                                      &replacement) == noErr, replacement != nil else { return false }
        }
        if let carbonHotkey { UnregisterEventHotKey(carbonHotkey) }
        carbonHotkey = replacement
        activeCarbonID = replacement == nil ? nil : nextCarbonID
        shortcut = value
        registrationFailed = false
        if save {
            UserDefaults.standard.set(value.flatMap { try? JSONEncoder().encode($0) },
                                      forKey: SettingsKey.launchShortcut)
        }
        return true
    }

    private func handleEvent(_ event: NSEvent) {
        guard !isRecording else { return }
        if event.type == .flagsChanged {
            handleFlags(event)
        } else if shiftKeyDown {
            otherKeyPressed = true
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let keyCode = event.keyCode
        guard keyCode == 56 || keyCode == 60 else {
            otherKeyPressed = true
            return
        }

        let shiftIsDown = event.modifierFlags.contains(.shift)

        if shiftIsDown && !shiftKeyDown {
            shiftKeyDown = true
            otherKeyPressed = false
        } else if !shiftIsDown && shiftKeyDown {
            shiftKeyDown = false

            guard !otherKeyPressed else {
                resetTaps()
                return
            }

            shiftTapCount += 1

            // 取消上一个待执行的计时器
            tapTimer?.cancel()

            if shiftTapCount >= 4 {
                // 立即触发4次
                resetTaps()
                DispatchQueue.main.async { self.onQuadShift?() }
                return
            }

            // 设置新计时器：如果在 tapWindow 内没有更多按键，则根据次数触发
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let count = self.shiftTapCount
                self.shiftTapCount = 0
                if count >= 2, self.shortcut == nil {
                    self.onHotkey?()
                }
            }
            tapTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + tapWindow, execute: work)
        }
    }

    private func resetTaps() {
        shiftTapCount = 0
        tapTimer?.cancel()
        tapTimer = nil
    }
}
