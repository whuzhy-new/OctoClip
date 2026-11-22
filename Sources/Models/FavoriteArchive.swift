import Foundation

struct FavoriteArchive: Codable {
    private let version: Int
    let clips: [ClipboardItem]

    init(_ clips: [ClipboardItem]) {
        version = 1
        self.clips = clips
    }

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func read(_ file: URL) throws -> [ClipboardItem] {
        let archive = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file, options: .mappedIfSafe))
        guard archive.version == 1 else { throw CocoaError(.fileReadUnknown) }
        return archive.clips
    }
}
