import AppKit
import Combine

final class FavoriteSync: ObservableObject {
    static let shared = FavoriteSync(store: .shared)

    @Published private(set) var folder: URL?
    @Published private(set) var selectedIDs: Set<UUID> = []
    @Published private(set) var incoming: [ClipboardItem] = []
    @Published private(set) var message: String?
    @Published private(set) var isWorking = false

    private let store: ClipboardStore
    private let defaults: UserDefaults
    private let worker = DispatchQueue(label: "com.octoclip.favorite-sync", qos: .utility)
    private let deviceID: UUID
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var dirty = false
    private var disconnecting = false
    private var remoteFiles: [URL: RemoteFile] = [:]

    private struct RemoteFile {
        let size: Int
        let modified: Date?
        let clips: [ClipboardItem]
    }

    private static let bookmarkKey = "favoriteSyncFolder"
    private static let deviceKey = "favoriteSyncDevice"
    private static let selectionKey = "favoriteSyncItems"
    private static let maximumArchiveSize = 64 * 1024 * 1024

    init(store: ClipboardStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let id = defaults.string(forKey: Self.deviceKey).flatMap(UUID.init(uuidString:)) ?? UUID()
        deviceID = id
        defaults.set(id.uuidString, forKey: Self.deviceKey)
        selectedIDs = Set((defaults.stringArray(forKey: Self.selectionKey) ?? []).compactMap(UUID.init(uuidString:)))
        if let bookmark = defaults.data(forKey: Self.bookmarkKey) {
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                folder = url
                if stale { try saveBookmark(url) }
            } catch {
                message = "无法打开同步文件夹，请重新连接。"
            }
        }
    }

    func start() {
        observation = store.$favoriteItems.dropFirst().sink { [weak self] _ in
            guard let self, self.folder != nil else { return }
            self.dirty = true
            DispatchQueue.main.async { self.refresh() }
        }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        dirty = folder != nil
        refresh()
    }

    func connect(_ url: URL) {
        guard folder == nil, !isWorking else { return }
        do {
            let location = url.appendingPathComponent("OctoClip Favorites", isDirectory: true)
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            try saveBookmark(url)
            selectedIDs = []
            saveSelection()
            folder = url
            message = nil
            dirty = true
            refresh()
        } catch {
            message = "无法连接同步文件夹。请检查文件夹的访问权限。"
        }
    }

    func disconnect() {
        guard let folder, !isWorking else { return }
        disconnecting = true
        isWorking = true
        let own = ownFile(in: folder)
        worker.async { [weak self] in
            let success: Bool
            do {
                try Self.publish([], to: own)
                success = true
            } catch {
                success = false
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.disconnecting = false
                self.isWorking = false
                guard success else {
                    self.message = "无法移除本机共享副本，请恢复文件夹访问后重试。"
                    return
                }
                self.defaults.removeObject(forKey: Self.bookmarkKey)
                self.selectedIDs = []
                self.saveSelection()
                self.folder = nil
                self.incoming = []
                self.remoteFiles = [:]
                self.message = nil
                self.dirty = false
            }
        }
    }

    func toggle(_ item: ClipboardItem) {
        guard folder != nil, !disconnecting, canPublish(item) else { return }
        if selectedIDs.remove(item.id) == nil { selectedIDs.insert(item.id) }
        saveSelection()
        dirty = true
        refresh()
    }

    func canPublish(_ item: ClipboardItem) -> Bool {
        item.type != .file && store.isFavorite(item)
    }

    func refresh() {
        guard let folder, !isWorking else { return }
        let selection = store.favoriteItems.filter { selectedIDs.contains($0.id) && $0.type != .file }
        let pending = dirty
        dirty = false
        isWorking = true
        let own = ownFile(in: folder)
        let previous = remoteFiles
        worker.async { [weak self] in
            var failure: String?
            if pending {
                do { try Self.publish(selection, to: own) }
                catch {
                    failure = (error as? CocoaError)?.code == .fileWriteOutOfSpace ?
                        "共享的收藏超过 64 MB，请减少同步条目。" : "收藏上传失败，请检查同步文件夹。"
                }
            }
            let archive = try? Self.readIncoming(beside: own, previous: previous)
            let publishFailed = failure != nil
            let notice = failure ?? (archive == nil ? "无法读取同步文件夹。" :
                                      (archive?.hasUnreadableFile == true ? "部分共享收藏暂时无法读取。" : nil))
            DispatchQueue.main.async {
                guard let self else { return }
                let moreChanges = self.dirty
                self.dirty = moreChanges || publishFailed
                if let archive {
                    self.remoteFiles = archive.files
                    if archive.changed {
                        var seen: Set<UUID> = []
                        self.incoming = archive.files.sorted { $0.key.path < $1.key.path }
                            .flatMap { $0.value.clips.filter { seen.insert($0.id).inserted } }
                            .sorted { $0.timestamp > $1.timestamp }
                    }
                }
                self.message = notice
                self.isWorking = false
                if moreChanges { self.refresh() }
            }
        }
    }

    func finish() {
        timer?.invalidate()
        timer = nil
        guard let folder, !disconnecting else {
            worker.sync {}
            return
        }
        let pending = dirty
        let own = ownFile(in: folder)
        let selection = store.favoriteItems.filter { selectedIDs.contains($0.id) && $0.type != .file }
        worker.sync {
            if pending { try? Self.publish(selection, to: own) }
        }
    }

    private func saveBookmark(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.bookmarkKey)
    }

    private func saveSelection() {
        defaults.set(selectedIDs.map(\.uuidString), forKey: Self.selectionKey)
    }

    private func ownFile(in folder: URL) -> URL {
        folder.appendingPathComponent("OctoClip Favorites", isDirectory: true)
            .appendingPathComponent(deviceID.uuidString + ".json")
    }

    private static func publish(_ clips: [ClipboardItem], to file: URL) throws {
        if clips.isEmpty {
            do { try FileManager.default.removeItem(at: file) }
            catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {}
            return
        }
        let data = try FavoriteArchive(clips).encode()
        guard data.count <= maximumArchiveSize else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: file, options: .atomic)
    }

    private static func readIncoming(beside own: URL, previous: [URL: RemoteFile]) throws
        -> (files: [URL: RemoteFile], changed: Bool, hasUnreadableFile: Bool) {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey,
                                         .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let urls = try manager.contentsOfDirectory(at: own.deletingLastPathComponent(),
                                                   includingPropertiesForKeys: Array(keys), options: [])
        var files: [URL: RemoteFile] = [:]
        var changed = false
        var unreadable = false
        for url in urls where url != own && url.pathExtension == "json" {
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { continue }
            let old = previous[url]
            do {
                let info = try url.resourceValues(forKeys: keys)
                if info.isUbiquitousItem == true, info.ubiquitousItemDownloadingStatus == .notDownloaded {
                    try manager.startDownloadingUbiquitousItem(at: url)
                    files[url] = old
                    continue
                }
                guard info.isRegularFile == true, info.isSymbolicLink != true,
                      let size = info.fileSize, size <= maximumArchiveSize else { continue }
                if let old, old.size == size, old.modified == info.contentModificationDate {
                    files[url] = old
                } else {
                    let clips = try FavoriteArchive.read(url).filter { $0.type != .file }
                    files[url] = RemoteFile(size: size, modified: info.contentModificationDate, clips: clips)
                    changed = true
                }
            } catch {
                files[url] = old
                unreadable = true
            }
        }
        return (files, changed || files.count != previous.count, unreadable)
    }
}
