import Foundation
import AppKit

class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published var items: [ClipboardItem] = []
    @Published var favoriteIDs: Set<UUID> = []
    @Published var selectedItem: ClipboardItem?
    @Published var showingFavorites = false

    /// 最大条目数（从 UserDefaults 读取）
    private var maxItems: Int {
        let val = UserDefaults.standard.integer(forKey: SettingsKey.maxItems)
        if val <= 0 { return val == -1 ? Int.max : 200 }
        return val
    }

    /// 保留天数（从 UserDefaults 读取）
    private var retentionDays: Int {
        let val = UserDefaults.standard.integer(forKey: SettingsKey.retentionDays)
        return val == 0 ? 3 : val
    }

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClipboardApp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private var favURL: URL {
        saveURL.deletingLastPathComponent().appendingPathComponent("favorites.json")
    }

    private init() {
        load()
        loadFavorites()
        if retentionDays > 0 {
            purgeOlderThan(days: retentionDays)
        }
    }

    // MARK: - Items

    func add(_ item: ClipboardItem) {
        if let first = items.first, first.plainText == item.plainText,
           first.type == item.type, first.fileURLs == item.fileURLs {
            return
        }

        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        favoriteIDs.remove(item.id)
        save()
        saveFavorites()
    }

    func clear() {
        items.removeAll()
        favoriteIDs.removeAll()
        save()
        saveFavorites()
    }

    /// 应用设置变更：根据当前设置重新清理
    func applySettings() {
        if retentionDays > 0 {
            purgeOlderThan(days: retentionDays)
        }
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
            save()
        }
    }

    func purgeOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let before = items.count
        // 收藏的不清理
        items.removeAll { $0.timestamp < cutoff && !favoriteIDs.contains($0.id) }
        if items.count != before { save() }
    }

    // MARK: - Favorites

    var favoriteItems: [ClipboardItem] {
        items.filter { favoriteIDs.contains($0.id) }
    }

    func isFavorite(_ item: ClipboardItem) -> Bool {
        favoriteIDs.contains(item.id)
    }

    func toggleFavorite(_ item: ClipboardItem) {
        if favoriteIDs.contains(item.id) {
            favoriteIDs.remove(item.id)
        } else {
            favoriteIDs.insert(item.id)
        }
        saveFavorites()
    }

    // MARK: - Persistence

    private func save() {
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(self.items)
                try data.write(to: self.saveURL, options: .atomic)
            } catch {
                print("保存失败: \(error)")
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode([ClipboardItem].self, from: data)
            self.items = decoded
        } catch {
            print("加载失败: \(error)")
        }
    }

    private func saveFavorites() {
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(Array(self.favoriteIDs))
                try data.write(to: self.favURL, options: .atomic)
            } catch {
                print("收藏保存失败: \(error)")
            }
        }
    }

    private func loadFavorites() {
        guard FileManager.default.fileExists(atPath: favURL.path) else { return }
        do {
            let data = try Data(contentsOf: favURL)
            let decoded = try JSONDecoder().decode([UUID].self, from: data)
            self.favoriteIDs = Set(decoded)
        } catch {
            print("收藏加载失败: \(error)")
        }
    }
}
