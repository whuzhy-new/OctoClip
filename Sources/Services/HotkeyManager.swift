import AppKit
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()

    /// 双击 shift：唤出/隐藏面板
    var onHotkey: (() -> Void)?
    /// 4次 shift：切换收藏夹
    var onQuadShift: (() -> Void)?

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
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }

        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            self?.otherKeyPressed = true
        }

        print("[HotkeyManager] Shift 监听已启动（2次唤出 / 4次收藏夹）")
    }

    func unregister() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
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
                if count >= 2 {
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
