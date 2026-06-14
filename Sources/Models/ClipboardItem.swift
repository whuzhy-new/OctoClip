import AppKit

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

    var preview: String {
        switch type {
        case .text:
            return plainText?.prefix(200).replacingOccurrences(of: "\n", with: " ") ?? ""
        case .image:
            return "[图片]"
        case .file:
            return fileURLs?.map { $0.lastPathComponent }.joined(separator: ", ") ?? "[文件]"
        }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}
