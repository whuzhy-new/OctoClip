import AppKit
import Quartz

final class ClipPreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var urls: [URL] = []
    private var temporaryFolder: URL?
    private weak var panel: QLPreviewPanel?
    private var onClose: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }
    var hasItems: Bool { !urls.isEmpty }

    func open(_ item: ClipboardItem, onClose: @escaping () -> Void) throws {
        close()
        switch item.type {
        case .file:
            urls = (item.fileURLs ?? []).filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
        case .image:
            if let data = item.imageData {
                let ext = item.imageFormat == .jpeg ? "jpg" : (item.imageFormat?.rawValue ?? "png")
                urls = [try stage(data, filename: "图片.\(ext)")]
            }
        case .text:
            if let rtf = item.rtfData {
                urls = [try stage(rtf, filename: "文本.rtf")]
            } else if let html = item.htmlData {
                urls = [try stage(html, filename: "文本.html")]
            } else if let text = item.plainText {
                urls = [try stage(Data(text.utf8), filename: "文本.txt")]
            }
        }
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else {
            clear()
            throw CocoaError(.fileReadNoSuchFile)
        }
        self.panel = panel
        self.onClose = onClose
        panel.makeKeyAndOrderFront(nil)
        panel.updateController()
        guard panel.dataSource === self else {
            close()
            throw CocoaError(.fileReadUnknown)
        }
    }

    func beginControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
    }

    func endControl(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }

    func close() {
        let win = panel
        if win?.isVisible == true { win?.close() }
        if panel != nil || temporaryFolder != nil { clear() }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    func windowWillClose(_ notification: Notification) { clear() }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.charactersIgnoringModifiers == "\u{1b}" || event.charactersIgnoringModifiers == " " else {
            return false
        }
        close()
        return true
    }

    private func clear() {
        if let panel { endControl(panel) }
        panel = nil
        urls = []
        if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) }
        temporaryFolder = nil
        let completion = onClose
        onClose = nil
        completion?()
    }

    private func stage(_ data: Data, filename: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OctoClip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        temporaryFolder = folder
        let url = folder.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            clear()
            throw error
        }
    }
}
