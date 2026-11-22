import Foundation

struct ClipboardLibrary: Encodable {
    let history: [ClipboardItem]
    let favorites: [ClipboardItem]

    static let defaultDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClipboardApp", isDirectory: true)

    struct Snapshot {
        let library: ClipboardLibrary
        let hasDamagedHistory: Bool
        let hasDamagedLegacyFavorites: Bool
    }

    static func read(from directory: URL) throws -> Snapshot {
        let historyURL = directory.appendingPathComponent("history.json")
        let decoder = JSONDecoder()
        let rows: [ReadableRow<ClipboardItem>]

        if let data = try dataIfPresent(at: historyURL) {
            if let library = try? decoder.decode(ReadableLibrary.self, from: data) {
                let history = library.history?.compactMap(\.value) ?? []
                let favorites = library.favorites?.compactMap(\.value) ?? []
                return Snapshot(library: ClipboardLibrary(history: history, favorites: favorites),
                                hasDamagedHistory: library.history?.count != history.count ||
                                    library.favorites?.count != favorites.count,
                                hasDamagedLegacyFavorites: false)
            }
            rows = try decoder.decode([ReadableRow<ClipboardItem>].self, from: data)
        } else {
            rows = []
        }

        let history = rows.compactMap(\.value)
        var favorites: [ClipboardItem] = []
        var damagedFavorites = false
        do {
            if let data = try dataIfPresent(at: directory.appendingPathComponent("favorites.json")) {
                let savedIDs = try decoder.decode([ReadableRow<UUID>].self, from: data)
                let ids = Set(savedIDs.compactMap(\.value))
                favorites = history.filter { ids.contains($0.id) }
                damagedFavorites = savedIDs.contains { $0.value == nil }
            }
        } catch {
            damagedFavorites = true
        }
        return Snapshot(library: ClipboardLibrary(history: history, favorites: favorites),
                        hasDamagedHistory: rows.count != history.count,
                        hasDamagedLegacyFavorites: damagedFavorites)
    }

    private static func dataIfPresent(at url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}

// Decode each row independently so one unreadable item cannot hide the rest.
private struct ReadableRow<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) {
        value = try? Value(from: decoder)
    }
}

private struct ReadableLibrary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case history, favorites
    }

    let history: [ReadableRow<ClipboardItem>]?
    let favorites: [ReadableRow<ClipboardItem>]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.history) || container.contains(.favorites) else {
            throw DecodingError.keyNotFound(CodingKeys.history, .init(codingPath: decoder.codingPath,
                                                                     debugDescription: "Missing clipboard library"))
        }
        history = try? container.decode([ReadableRow<ClipboardItem>].self, forKey: .history)
        favorites = try? container.decode([ReadableRow<ClipboardItem>].self, forKey: .favorites)
    }
}
