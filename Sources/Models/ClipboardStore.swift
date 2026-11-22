import AppKit

class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore(directory: ClipboardLibrary.defaultDirectory)

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var favoriteItems: [ClipboardItem] = []
    @Published var showingFavorites = false
    @Published private(set) var recoveryFile: URL?
    @Published private(set) var saveFailed = false
    @Published private(set) var undoTitle: String?

    private let directory: URL
    private let defaults: UserDefaults
    private let writer = DispatchQueue(label: "com.octoclip.library", qos: .utility)
    private var historyBackup: URL?
    private var writeRevision = 0
    private var deletedItem: (item: ClipboardItem, favorite: Bool)?

    private var historyURL: URL { directory.appendingPathComponent("history.json") }
    private var legacyFavoritesURL: URL { directory.appendingPathComponent("favorites.json") }
    var canRetryReading: Bool { recoveryFile != nil && writeRevision == 0 }

    var retentionDays: Int {
        let value = defaults.integer(forKey: SettingsKey.retentionDays)
        return RetentionOption(rawValue: value) == nil ? RetentionOption.threeDays.rawValue : value
    }

    var maxItems: Int {
        let value = defaults.integer(forKey: SettingsKey.maxItems)
        return MaxItemsOption(rawValue: value) == nil ? MaxItemsOption.twoHundred.rawValue : value
    }

    init(directory: URL, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
        load()
        applySettings()
    }

    func add(_ item: ClipboardItem) {
        guard items.first?.hasSameContent(as: item) != true else { return }
        items.insert(item, at: 0)
        if maxItems > 0, items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    func deleteHistoryItem(_ item: ClipboardItem) {
        guard items.contains(item) else { return }
        items.removeAll { $0.id == item.id }
        deletedItem = (item, false)
        undoTitle = "已从历史删除"
        save()
    }

    func deleteHistory(ids: Set<UUID>) {
        let remaining = items.filter { !ids.contains($0.id) }
        guard remaining.count != items.count else { return }
        items = remaining
        deletedItem = nil
        undoTitle = nil
        save()
    }

    func undoDeletion() {
        guard let removed = deletedItem else { return }
        if removed.favorite {
            restore(removed.item, into: &favoriteItems)
        } else {
            restore(removed.item, into: &items)
        }
        deletedItem = nil
        undoTitle = nil
        save()
    }

    private func restore(_ item: ClipboardItem, into collection: inout [ClipboardItem]) {
        guard !collection.contains(item) else { return }
        let index = collection.firstIndex { $0.timestamp < item.timestamp } ?? collection.endIndex
        collection.insert(item, at: index)
    }

    func isFavorite(_ item: ClipboardItem) -> Bool {
        favoriteItems.contains(item)
    }

    func toggleFavorite(_ item: ClipboardItem) {
        if isFavorite(item) {
            favoriteItems.removeAll { $0.id == item.id }
            deletedItem = (item, true)
            undoTitle = "已取消收藏"
        } else {
            restore(item, into: &favoriteItems)
            if deletedItem?.item == item, deletedItem?.favorite == true {
                deletedItem = nil
                undoTitle = nil
            }
        }
        save()
    }

    func saveFavorite(_ item: ClipboardItem) {
        if let index = favoriteItems.firstIndex(of: item) {
            favoriteItems[index] = item
        } else {
            restore(item, into: &favoriteItems)
        }
        if deletedItem?.item == item, deletedItem?.favorite == true {
            deletedItem = nil
            undoTitle = nil
        }
        save()
    }

    func editMetadata(id: UUID, name: String?, sourceURL: URL?) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].name = name
            items[index].sourceURL = sourceURL
        }
        if let index = favoriteItems.firstIndex(where: { $0.id == id }) {
            favoriteItems[index].name = name
            favoriteItems[index].sourceURL = sourceURL
        }
        save()
    }

    @discardableResult
    func importFavorites(_ clips: [ClipboardItem]) -> Int {
        var seen = Set(favoriteItems.map(\.id))
        let new = clips.filter { seen.insert($0.id).inserted }
        if !new.isEmpty {
            favoriteItems = (favoriteItems + new).sorted { $0.timestamp > $1.timestamp }
            save()
        }
        return new.count
    }

    func expirationIDs(days: Int, now: Date = Date()) -> Set<UUID> {
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return []
        }
        let favoriteIDs = Set(favoriteItems.map(\.id))
        return Set(items.lazy.filter { $0.timestamp < cutoff && !favoriteIDs.contains($0.id) }.map(\.id))
    }

    private func retainedHistory(days: Int, limit: Int) -> [ClipboardItem] {
        let expired = expirationIDs(days: days)
        let retained = items.filter { !expired.contains($0.id) }
        return limit > 0 ? Array(retained.prefix(limit)) : retained
    }

    func settingsRemovalCount(days: Int, limit: Int) -> Int {
        items.count - retainedHistory(days: days, limit: limit).count
    }

    func saveSettings(days: Int, limit: Int) {
        defaults.set(days, forKey: SettingsKey.retentionDays)
        defaults.set(limit, forKey: SettingsKey.maxItems)
        applySettings()
    }

    func expireHistory() {
        let expired = expirationIDs(days: retentionDays)
        guard !expired.isEmpty else { return }
        items.removeAll { expired.contains($0.id) }
        save()
    }

    private func applySettings() {
        let retained = retainedHistory(days: retentionDays, limit: maxItems)
        guard retained.count != items.count else { return }
        items = retained
        save()
    }

    func retryPersistence() {
        if writeRevision == 0 {
            load()
            applySettings()
        } else {
            save()
        }
    }

    func finishSaving() {
        writer.sync {}
    }

    private func load() {
        recoveryFile = nil
        historyBackup = nil
        do {
            let snapshot = try ClipboardLibrary.read(from: directory)
            items = snapshot.library.history
            favoriteItems = snapshot.library.favorites
            if snapshot.hasDamagedLegacyFavorites { recoveryFile = legacyFavoritesURL }
            if snapshot.hasDamagedHistory { protectHistory() }
        } catch {
            protectHistory()
        }
    }

    private func protectHistory() {
        recoveryFile = historyURL
        historyBackup = directory.appendingPathComponent("history-unreadable-\(UUID().uuidString).json")
    }

    private func save() {
        let snapshot = ClipboardLibrary(history: items, favorites: favoriteItems)
        let backup = historyBackup
        let destination = historyURL
        let directory = self.directory
        writeRevision += 1
        let revision = writeRevision

        writer.async { [weak self] in
            var failed = false
            var preservedFile: URL?
            do {
                let data = try JSONEncoder().encode(snapshot)
                let files = FileManager.default
                try files.createDirectory(at: directory, withIntermediateDirectories: true)
                if let backup {
                    if !files.fileExists(atPath: backup.path) {
                        try files.copyItem(at: destination, to: backup)
                    }
                    preservedFile = backup
                }
                try data.write(to: destination, options: .atomic)
            } catch {
                failed = true
                print("保存剪贴板记录失败: \(error)")
            }

            DispatchQueue.main.async { [weak self, failed, preservedFile] in
                guard let self, self.writeRevision == revision else { return }
                self.saveFailed = failed
                if let preservedFile { self.recoveryFile = preservedFile }
            }
        }
    }
}
