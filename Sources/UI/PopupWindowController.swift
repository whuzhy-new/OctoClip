import AppKit
import Carbon
import SwiftUI
import Quartz

class KeyablePanel: NSPanel {
    var clipPreview: ClipPreview?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { clipPreview?.hasItems == true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { clipPreview?.beginControl(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { clipPreview?.endControl(panel) }
}

class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class PopupWindowController: ObservableObject {
    static let shared = PopupWindowController()

    enum KeyCommand {
        case move(Int)
        case escape
        case preview
        case spacePreview
        case pasteIndex(Int)
        case plainPaste
        case pasteNext
    }

    enum Destination {
        case clipboard, settings
    }

    @Published private(set) var presentation = 0
    @Published private(set) var commandHeld = false
    @Published var destination: Destination = .clipboard {
        didSet {
            if oldValue != destination, isShowing, let panel {
                fit(panel, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
    }
    var handleKeyCommand: ((KeyCommand) -> Bool)?
    var isVisible: Bool { isShowing }

    private var panel: NSPanel?
    private var isShowing = false
    private var isHandingOff = false
    private var visibilityRevision = 0
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private let clipPreview = ClipPreview()

    private init() {}

    func toggle() {
        guard !isHandingOff else { return }
        if isShowing {
            hide()
        } else {
            show(favorites: false)
        }
    }

    func show(favorites: Bool? = nil, destination: Destination = .clipboard) {
        guard !isHandingOff else { return }
        if let favorites { ClipboardStore.shared.showingFavorites = favorites }
        self.destination = destination
        guard !isShowing else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = frontmost
        }
        PasteService.shared.clearFeedback()
        presentPanel()
    }

    private func presentPanel() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        fit(panel)

        visibilityRevision += 1
        isShowing = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }
        presentation += 1
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide(restoreFocus: false)
        }
    }

    private func fit(_ panel: NSPanel, animate: Bool = false) {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let available = screen.visibleFrame.insetBy(dx: PanelStyle.screenMargin, dy: PanelStyle.screenMargin)
        let preferred = destination == .settings ? PanelStyle.settingsSize : PanelStyle.preferredSize
        let shadowMargin = PanelStyle.windowShadowInset * 2
        let width = min(preferred.width + shadowMargin, available.width)
        let height = min(preferred.height + shadowMargin, available.height)
        panel.setFrame(NSRect(x: available.midX - width / 2, y: available.midY - height / 2,
                              width: width, height: height), display: true, animate: animate)
    }

    private func stopOutsideMonitoring() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
    }

    func hide(restoreFocus: Bool = true) {
        guard let panel, isShowing, panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        isShowing = false
        commandHeld = false
        clipPreview.close()
        stopOutsideMonitoring()
        visibilityRevision += 1
        let revision = visibilityRevision
        let finish = { [weak self] in
            guard let self, self.visibilityRevision == revision else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            if restoreFocus, self.isFrontmost(NSRunningApplication.current), let target = self.previousApp {
                self.activate(target)
            }
            self.previousApp = nil
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finish()
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: finish)
        }
    }

    func handOffForPaste(completion: @escaping (NSRunningApplication?) -> Void) {
        guard let panel, isShowing, !isHandingOff, let target = previousApp, !target.isTerminated else {
            completion(nil)
            return
        }
        isHandingOff = true
        isShowing = false
        commandHeld = false
        clipPreview.close()
        stopOutsideMonitoring()
        visibilityRevision += 1
        panel.orderOut(nil)
        panel.alphaValue = 1

        if isFrontmost(NSRunningApplication.current) { activate(target) }
        waitForTarget(target, attempts: 7, completion: completion)
    }

    func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private func activate(_ target: NSRunningApplication) {
        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: target) }
        target.activate(options: [])
    }

    private func waitForTarget(_ target: NSRunningApplication, attempts: Int,
                               completion: @escaping (NSRunningApplication?) -> Void) {
        if !target.isTerminated, isFrontmost(target) {
            completion(target)
            return
        }
        guard attempts > 0, !target.isTerminated, isFrontmost(NSRunningApplication.current) else {
            completion(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.waitForTarget(target, attempts: attempts - 1, completion: completion)
        }
    }

    func finishPasteHandoff(reopen: Bool) {
        guard isHandingOff else { return }
        isHandingOff = false
        if reopen {
            presentPanel()
        } else {
            previousApp = nil
        }
    }

    func showPreview(_ item: ClipboardItem, onClose: @escaping () -> Void) throws {
        try clipPreview.open(item) { [weak self] in
            guard let self, self.isShowing else { return }
            DispatchQueue.main.async {
                guard self.isShowing, !self.clipPreview.isVisible else { return }
                self.panel?.makeKey()
                onClose()
            }
        }
    }

    func presentFilePanel(_ dialog: NSSavePanel, completion: @escaping (URL) -> Void) {
        guard let panel, isShowing, panel.attachedSheet == nil else { return }
        dialog.beginSheetModal(for: panel) { response in
            guard response == .OK, let url = dialog.url else { return }
            completion(url)
        }
    }

    private func createPanel() {
        let hostingView = ClickableHostingView(rootView: PopupView())
        hostingView.autoresizingMask = [.width, .height]
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: PanelStyle.preferredSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "OctoClip"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hostingView
        panel.animationBehavior = .none
        panel.clipPreview = clipPreview
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self, weak panel] event in
            guard let self, let panel, self.isShowing else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.type == .keyDown, event.window is QLPreviewPanel, self.clipPreview.isVisible,
               modifiers.isEmpty, [kVK_Escape, kVK_Space].contains(Int(event.keyCode)) {
                self.clipPreview.close()
                return nil
            }
            guard event.window === panel, panel.attachedSheet == nil else {
                return event
            }
            if event.type == .flagsChanged {
                self.commandHeld = modifiers.contains(.command)
                return event
            }
            if let recorder = HotkeyManager.shared.recordingHandler {
                if !event.isARepeat { recorder(event) }
                return nil
            }
            if let editor = panel.firstResponder as? NSTextView {
                if editor.hasMarkedText() { return event }
                if Int(event.keyCode) == kVK_ANSI_A, modifiers == .command {
                    editor.selectAll(nil)
                    return nil
                }
            }

            switch Int(event.keyCode) {
            case kVK_Escape:
                if self.handleKeyCommand?(.escape) != true { self.hide() }
                return nil
            case kVK_UpArrow, kVK_DownArrow:
                guard modifiers.isEmpty else { return event }
                let offset = Int(event.keyCode) == kVK_UpArrow ? -1 : 1
                return self.handleKeyCommand?(.move(offset)) == true ? nil : event
            case kVK_Space where modifiers.isEmpty && !(panel.firstResponder is NSTextView):
                return self.handleKeyCommand?(.spacePreview) == true ? nil : event
            case kVK_ANSI_Y where modifiers == .command:
                return self.handleKeyCommand?(.preview) == true ? nil : event
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if modifiers == .shift, self.handleKeyCommand?(.plainPaste) == true { return nil }
                return event
            default:
                if modifiers == .command, let key = event.charactersIgnoringModifiers,
                   let number = Int(key), (1...9).contains(number),
                   self.handleKeyCommand?(.pasteIndex(number - 1)) == true { return nil }
                return event
            }
        }
    }
}
