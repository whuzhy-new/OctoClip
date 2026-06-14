import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 请求辅助功能权限（粘贴功能需要）
        PasteService.ensureAccessibility()

        // 菜单栏图标
        setupMenuBar()

        // 启动剪切板监听
        ClipboardMonitor.shared.start()

        // 注册 Shift 热键
        HotkeyManager.shared.onHotkey = {
            DispatchQueue.main.async {
                ClipboardStore.shared.showingFavorites = false
                PopupWindowController.shared.toggle()
            }
        }
        HotkeyManager.shared.onQuadShift = {
            DispatchQueue.main.async {
                ClipboardStore.shared.showingFavorites = true
                PopupWindowController.shared.show()
            }
        }
        HotkeyManager.shared.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        HotkeyManager.shared.unregister()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = makeMenuBarIcon()
            button.image?.isTemplate = true
            button.toolTip = "OctoClip — Double Shift 打开"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开剪切板", action: #selector(openPopup), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openPopup() {
        PopupWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// 用代码绘制菜单栏剪切板图标（与 AppIcon.svg 风格一致）
    private func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard NSGraphicsContext.current != nil else { return false }

            let scale: CGFloat = 18.0 / 1024.0

            // 剪切板主体
            let boardRect = CGRect(x: 272 * scale, y: (1024 - 840) * scale,
                                   width: 480 * scale, height: 620 * scale)
            let boardPath = NSBezierPath(roundedRect: boardRect, xRadius: 36 * scale, yRadius: 36 * scale)
            NSColor.black.setFill()
            boardPath.fill()

            // 顶部夹子
            let clipRect = CGRect(x: 392 * scale, y: (1024 - 272) * scale,
                                  width: 240 * scale, height: 104 * scale)
            let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: 52 * scale, yRadius: 52 * scale)
            clipPath.fill()

            // 夹子内凹
            let holeRect = CGRect(x: 432 * scale, y: (1024 - 248) * scale,
                                  width: 160 * scale, height: 56 * scale)
            let holePath = NSBezierPath(roundedRect: holeRect, xRadius: 28 * scale, yRadius: 28 * scale)
            NSColor.white.setFill()
            holePath.fill()

            // 内容线条
            NSColor.white.setFill()
            let lines: [(CGFloat, CGFloat, CGFloat)] = [
                (328, 340, 300),
                (328, 380, 368),
                (328, 460, 260),
                (328, 500, 340),
                (328, 570, 320),
                (328, 610, 280),
            ]
            for (x, y, w) in lines {
                let lineRect = CGRect(x: x * scale, y: (1024 - y - 22) * scale,
                                      width: w * scale, height: 22 * scale)
                let linePath = NSBezierPath(roundedRect: lineRect, xRadius: 11 * scale, yRadius: 11 * scale)
                linePath.fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
