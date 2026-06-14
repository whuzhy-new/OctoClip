import AppKit

enum PasteMode {
    case original
    case plainText
    case noNewlines
}

class PasteService {
    static let shared = PasteService()

    private init() {}

    /// 检查并请求辅助功能权限
    static func ensureAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 写入剪切板 → 隐藏面板 → 激活前台 app → 粘贴
    func pasteToFrontApp(_ item: ClipboardItem, mode: PasteMode) {
        copyToClipboard(item, mode: mode)
        PopupWindowController.shared.hideAndActivatePreviousApp {
            self.simulatePaste()
        }
    }

    /// 模拟 Cmd+V - 两种方式都试
    private func simulatePaste() {
        // 方式1: AppleScript (更可靠)
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        // 如果 AppleScript 失败，用 CGEvent 兜底
        if error != nil {
            let src = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    /// 替换剪切板内容
    func copyToClipboard(_ item: ClipboardItem, mode: PasteMode) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.type {
        case .text:
            copyText(item, mode: mode, to: pb)
        case .image:
            if let data = item.imageData {
                let type: NSPasteboard.PasteboardType
                switch item.imageFormat {
                case .gif: type = NSPasteboard.PasteboardType("com.compuserve.gif")
                case .jpeg: type = NSPasteboard.PasteboardType("public.jpeg")
                default: type = .png
                }
                pb.setData(data, forType: type)
            }
        case .file:
            if let urls = item.fileURLs {
                pb.writeObjects(urls as [NSURL])
            }
        }
    }

    private func copyText(_ item: ClipboardItem, mode: PasteMode, to pb: NSPasteboard) {
        switch mode {
        case .original:
            if let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
            if let html = item.htmlData { pb.setData(html, forType: .html) }
            if let text = item.plainText { pb.setString(text, forType: .string) }
        case .plainText:
            if let text = item.plainText { pb.setString(text, forType: .string) }
        case .noNewlines:
            if let text = item.plainText {
                let cleaned = text
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: "")
                pb.setString(cleaned, forType: .string)
            }
        }
    }
}
