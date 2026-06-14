import AppKit
import SwiftUI

// 自定义 Panel，允许接受键盘输入
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// 自定义 HostingView，确保首次点击能正确传递
class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class PopupWindowController {
    static let shared = PopupWindowController()

    private var panel: NSPanel?
    private var isShowing = false
    private var clickOutsideMonitor: Any?
    private var previousApp: NSRunningApplication?

    private init() {}

    func toggle() {
        isShowing ? hide() : show()
    }

    func show() {
        if panel == nil { createPanel() }
        guard let panel = panel, let screen = NSScreen.main else { return }

        previousApp = NSWorkspace.shared.frontmostApplication

        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 620
        let panelHeight: CGFloat = 480

        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.midY - panelHeight / 2
        let targetFrame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        panel.setFrame(targetFrame, display: true)
        panel.alphaValue = 0

        // 通过 layer transform 实现真正的视觉缩放
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            contentView.layer?.position = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
            contentView.layer?.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            panel.contentView?.layer?.transform = CATransform3DIdentity
        }

        isShowing = true

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        guard let panel = panel, isShowing else { return }
        isShowing = false
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.contentView?.layer?.transform = CATransform3DMakeScale(0.94, 0.94, 1)
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.contentView?.layer?.transform = CATransform3DIdentity
            self?.previousApp = nil
        })
    }

    /// 隐藏窗口并激活之前的 app，完成后回调
    func hideAndActivatePreviousApp(completion: @escaping () -> Void) {
        guard let panel = panel else { completion(); return }
        isShowing = false
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.contentView?.layer?.transform = CATransform3DMakeScale(0.94, 0.94, 1)
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.contentView?.layer?.transform = CATransform3DIdentity

            if let app = self?.previousApp {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            self?.pollActivation(attempts: 4, completion: completion)
        })
    }

    private func pollActivation(attempts: Int, completion: @escaping () -> Void) {
        if attempts <= 0 || NSWorkspace.shared.frontmostApplication == previousApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                completion()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.pollActivation(attempts: attempts - 1, completion: completion)
            }
        }
    }

    private func createPanel() {
        let contentView = PopupView()
        let hostingView = ClickableHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]

        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = hostingView
        p.animationBehavior = .utilityWindow

        // ESC 关闭
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }

        self.panel = p
    }
}
