import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var expirationTimer: Timer?
    private var statusObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 请求辅助功能权限（粘贴功能需要）
        PasteService.ensureAccessibility()

        // 菜单栏图标
        setupMenuBar()

        // 启动剪切板监听
        ClipboardMonitor.shared.start()
        let store = ClipboardStore.shared
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            store.expireHistory()
        }
        RunLoop.main.add(timer, forMode: .common)
        expirationTimer = timer

        // 注册 Shift 热键
        HotkeyManager.shared.onHotkey = {
            DispatchQueue.main.async {
                PopupWindowController.shared.toggle()
            }
        }
        HotkeyManager.shared.onQuadShift = {
            DispatchQueue.main.async {
                PopupWindowController.shared.show(favorites: true)
            }
        }
        HotkeyManager.shared.register()
        statusObservation = ClipboardMonitor.shared.$pausedUntil.combineLatest(HotkeyManager.shared.$shortcut)
            .sink { [weak self] pausedUntil, shortcut in
                self?.updateStatus(paused: pausedUntil != nil, shortcut: shortcut?.label ?? "连按两次 Shift")
            }
        FavoriteSync.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        expirationTimer?.invalidate()
        HotkeyManager.shared.unregister()
        FavoriteSync.shared.finish()
        ClipboardStore.shared.finishSaving()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatus(paused: Bool, shortcut: String) {
        guard let button = statusItem.button else { return }
        let label = paused ? "OctoClip · 记录已暂停" : "OctoClip"
        let icon: LucideIcon = paused ? .circlePause : .clipboard
        button.image = icon.menuBarImage(label: label)
        button.toolTip = "\(label) · \(shortcut)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "打开剪切板", action: #selector(openPopup), keyEquivalent: ""))
        let queue = PasteQueue.shared
        if !queue.items.isEmpty {
            if queue.manualPayload != nil {
                menu.addItem(NSMenuItem(title: "已粘贴，继续队列", action: #selector(confirmManualPaste), keyEquivalent: ""))
            } else {
                menu.addItem(NSMenuItem(title: "粘贴队列下一条（剩余 \(queue.items.count) 条）",
                                        action: #selector(pasteNext), keyEquivalent: ""))
            }
            menu.addItem(NSMenuItem(title: "清空粘贴队列", action: #selector(clearQueue), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        if let deadline = ClipboardMonitor.shared.pausedUntil {
            let title = deadline == .distantFuture ? "恢复记录" :
                "恢复记录（暂停至 \(DateFormatter.localizedString(from: deadline, dateStyle: .none, timeStyle: .short))）"
            menu.addItem(NSMenuItem(title: title, action: #selector(resumeCapture), keyEquivalent: ""))
        } else {
            let item = NSMenuItem(title: "暂停记录", action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for (title, minutes) in [("15 分钟", 15), ("1 小时", 60), ("直到手动恢复", 0)] {
                let duration = NSMenuItem(title: title, action: #selector(pauseCapture(_:)), keyEquivalent: "")
                duration.tag = minutes
                duration.target = self
                choices.addItem(duration)
            }
            item.submenu = choices
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }
    }

    @objc private func pauseCapture(_ sender: NSMenuItem) {
        ClipboardMonitor.shared.pause(minutes: sender.tag == 0 ? nil : sender.tag)
    }

    @objc private func resumeCapture() { ClipboardMonitor.shared.resume() }

    @objc private func pasteNext() {
        let window = PopupWindowController.shared
        window.show()
        DispatchQueue.main.async { _ = window.handleKeyCommand?(.pasteNext) }
    }

    @objc private func confirmManualPaste() { PasteQueue.shared.confirmManualPaste() }

    @objc private func clearQueue() { PasteQueue.shared.clear() }

    @objc private func openPopup() {
        PopupWindowController.shared.show()
    }

    @objc private func openSettings() {
        PopupWindowController.shared.show(destination: .settings)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
