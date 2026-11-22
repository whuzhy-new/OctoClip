import AppKit

struct ClipSource: Codable, Equatable {
    let bundleID: String
    let name: String
}

enum ClipboardItemType: String, Codable {
    case text
    case image
    case file
}

enum ImageFormat: String, Codable {
    case png
    case gif
    case jpeg
    case heic
    case webp
    case tiff

    var pasteboardType: NSPasteboard.PasteboardType {
        switch self {
        case .png: return .png
        case .gif: return .init("com.compuserve.gif")
        case .jpeg: return .init("public.jpeg")
        case .heic: return .init("public.heic")
        case .webp: return .init("org.webmproject.webp")
        case .tiff: return .tiff
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    let plainText: String?
    let rtfData: Data?
    let htmlData: Data?
    let imageData: Data?
    let imageFormat: ImageFormat?
    let fileURLs: [URL]?
    var source: ClipSource? = nil
    var sourceURL: URL? = nil
    var name: String? = nil
    var group: String? = nil
    var template: Bool? = nil

    static func text(_ value: String, id: UUID = UUID(), timestamp: Date = Date()) -> ClipboardItem {
        ClipboardItem(id: id, type: .text, timestamp: timestamp, plainText: value,
                      rtfData: nil, htmlData: nil, imageData: nil, imageFormat: nil, fileURLs: nil)
    }

    var richText: NSAttributedString? {
        if let htmlData, let text = NSAttributedString(html: htmlData, documentAttributes: nil) {
            return text
        }
        if let rtfData {
            return NSAttributedString(rtf: rtfData, documentAttributes: nil)
        }
        return nil
    }

    var readableText: String? {
        if let plainText, !plainText.isEmpty { return plainText }
        return richText?.string ?? plainText
    }

    var templateFields: [String] {
        guard template == true, let text = readableText else { return [] }
        return ClipDocument.fieldNames(in: text)
    }

    var preview: String {
        switch type {
        case .text:
            return readableText?.prefix(200).replacingOccurrences(of: "\n", with: " ") ?? ""
        case .image:
            return "[图片]"
        case .file:
            return fileURLs?.map { $0.lastPathComponent }.joined(separator: ", ") ?? "[文件]"
        }
    }

    func matchesSearch(_ query: String) -> Bool {
        let content = type == .text ? readableText : preview
        return [content, name, group, source?.name, sourceURL?.absoluteString].contains {
            $0?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var supportsTextRecognition: Bool {
        type == .image && imageData != nil && imageFormat != .gif
    }

    var displayTitle: String {
        if let name { return name }
        if type == .image { return imageFormat == .gif ? "GIF" : "图片" }
        return preview.isEmpty ? "剪贴板条目" : preview
    }

    func hasSameContent(as other: ClipboardItem) -> Bool {
        guard type == other.type else { return false }
        switch type {
        case .text:
            return plainText == other.plainText && rtfData == other.rtfData && htmlData == other.htmlData
        case .image:
            return imageFormat == other.imageFormat && imageData == other.imageData
        case .file:
            return fileURLs == other.fileURLs
        }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}
