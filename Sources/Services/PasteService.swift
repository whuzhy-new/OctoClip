import AppKit
import Carbon

enum PasteMode {
    case original
    case plainText
    case noNewlines
    case trimmed
    case markdown
}

class PasteService: ObservableObject {
    static let shared = PasteService()

    struct Feedback {
        let message: String
        var canCopy = false
    }

    enum Outcome {
        case sent
        case copiedForManualPaste
    }

    @Published private(set) var isPasting = false
    @Published private(set) var feedback: Feedback?

    private var fallback: (item: ClipboardItem, mode: PasteMode, completion: ((Outcome) -> Void)?)?

    private init() {}

    static func ensureAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func pasteToFrontApp(_ item: ClipboardItem, mode: PasteMode, completion: ((Outcome) -> Void)? = nil) {
        guard !isPasting else { return }
        clearFeedback()
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            offerCopy(item, mode: mode, message: "缺少辅助功能权限。", completion: completion)
            return
        }

        let objects = pasteboardObjects(for: item, mode: mode)
        guard !objects.isEmpty else {
            feedback = Feedback(message: "此条目没有可粘贴的内容。")
            return
        }
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            offerCopy(item, mode: mode, message: "无法发送粘贴快捷键。", completion: completion)
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        isPasting = true
        let window = PopupWindowController.shared
        window.handOffForPaste { target in
            defer { self.isPasting = false }
            guard let target, window.isFrontmost(target) else {
                self.offerCopy(item, mode: mode, message: "原应用未就绪。", completion: completion)
                window.finishPasteHandoff(reopen: true)
                return
            }
            guard self.write(objects, to: .general) else {
                self.offerCopy(item, mode: mode, message: "无法写入剪贴板。", completion: completion)
                window.finishPasteHandoff(reopen: true)
                return
            }
            guard window.isFrontmost(target) else {
                self.feedback = Feedback(message: "已复制，切回原应用按 ⌘V。")
                completion?(.copiedForManualPaste)
                window.finishPasteHandoff(reopen: true)
                return
            }
            keyDown.postToPid(target.processIdentifier)
            keyUp.postToPid(target.processIdentifier)
            completion?(.sent)
            window.finishPasteHandoff(reopen: false)
        }
    }

    func copyFallback() {
        guard let fallback, !isPasting else { return }
        if copyToClipboard(fallback.item, mode: fallback.mode) {
            clearFeedback()
            feedback = Feedback(message: "已复制，切回应用按 ⌘V。")
            fallback.completion?(.copiedForManualPaste)
        } else {
            feedback = Feedback(message: "复制失败。", canCopy: true)
        }
    }

    func clearFeedback() {
        fallback = nil
        feedback = nil
    }

    func report(_ message: String) {
        clearFeedback()
        feedback = Feedback(message: message)
    }

    private func offerCopy(_ item: ClipboardItem, mode: PasteMode, message: String, completion: ((Outcome) -> Void)?) {
        fallback = (item, mode, completion)
        feedback = Feedback(message: message, canCopy: true)
    }

    @discardableResult
    func copyToClipboard(_ item: ClipboardItem, mode: PasteMode, to pasteboard: NSPasteboard = .general) -> Bool {
        write(pasteboardObjects(for: item, mode: mode), to: pasteboard)
    }

    private func write(_ objects: [NSPasteboardWriting], to pasteboard: NSPasteboard) -> Bool {
        guard !objects.isEmpty else { return false }
        pasteboard.clearContents()
        let written = pasteboard.writeObjects(objects)
        if pasteboard === NSPasteboard.general || pasteboard.name == .general {
            ClipboardMonitor.shared.ignoreCurrentChange()
        }
        return written
    }

    private func pasteboardObjects(for item: ClipboardItem, mode: PasteMode) -> [NSPasteboardWriting] {
        let entry = NSPasteboardItem()
        switch item.type {
        case .text:
            if mode == .original {
                if let rtf = item.rtfData { entry.setData(rtf, forType: .rtf) }
                if let html = item.htmlData { entry.setData(html, forType: .html) }
            }
            let text: String?
            switch mode {
            case .original: text = item.plainText
            case .plainText: text = item.readableText
            case .noNewlines:
                text = item.readableText?.replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: .newlines).joined(separator: " ")
            case .trimmed: text = item.readableText?.trimmingCharacters(in: .whitespacesAndNewlines)
            case .markdown: text = ClipDocument.richMarkdown(item)
            }
            if let text { entry.setString(text, forType: .string) }
        case .image:
            if let data = item.imageData {
                entry.setData(data, forType: (item.imageFormat ?? .png).pasteboardType)
            }
        case .file:
            return (item.fileURLs ?? []).map { $0 as NSURL }
        }
        return entry.types.isEmpty ? [] : [entry]
    }
}
