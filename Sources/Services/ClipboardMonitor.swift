import AppKit

class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    @Published private(set) var pausedUntil = UserDefaults.standard.object(forKey: SettingsKey.capturePausedUntil) as? Date
    @Published private(set) var excludedApps = ClipboardPasteboard.excludedApps(in: .standard)
    private var changeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var foregroundAppIDs: Set<String> = []

    private init() {}

    func start() {
        guard timer == nil else { return }
        if pausedUntil.map({ $0 <= Date() }) == true { resume() }
        let workspace = NSWorkspace.shared
        if let id = workspace.frontmostApplication?.bundleIdentifier { foregroundAppIDs.insert(id) }
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let id = app.bundleIdentifier {
                self?.foregroundAppIDs.insert(id)
            }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        foregroundAppIDs.removeAll()
    }

    func pause(minutes: Int?) {
        updatePause(minutes.map { Date().addingTimeInterval(Double($0) * 60) } ?? .distantFuture)
    }

    func resume() { updatePause(nil) }

    func ignoreCurrentChange() {
        changeCount = NSPasteboard.general.changeCount
    }

    func excludeApplication(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return false }
        if excludedApps.contains(where: { $0.bundleID == id }) { return true }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        replaceExclusions(excludedApps + [ClipSource(bundleID: id, name: name)])
        return true
    }

    func includeApplication(_ bundleID: String) {
        replaceExclusions(excludedApps.filter { $0.bundleID != bundleID })
    }

    private func updatePause(_ deadline: Date?) {
        ignoreCurrentChange()
        pausedUntil = deadline
        UserDefaults.standard.set(deadline, forKey: SettingsKey.capturePausedUntil)
    }

    private func replaceExclusions(_ apps: [ClipSource]) {
        excludedApps = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        UserDefaults.standard.set(try? JSONEncoder().encode(excludedApps), forKey: SettingsKey.excludedApps)
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let app = NSWorkspace.shared.frontmostApplication
        let currentAppIDs = Set([app?.bundleIdentifier].compactMap { $0 })
        let candidateAppIDs = foregroundAppIDs.union(currentAppIDs)
        foregroundAppIDs = currentAppIDs
        if let pausedUntil {
            if pausedUntil <= Date() { resume() }
            else { ignoreCurrentChange() }
            return
        }
        let snapshot = pb.changeCount
        guard snapshot != changeCount else { return }
        changeCount = snapshot
        let item = ClipboardPasteboard.readItem(from: pb, excludedApps: excludedApps,
                                                ownBundleID: Bundle.main.bundleIdentifier, activeApp: app,
                                                candidateAppIDs: candidateAppIDs)
        if pb.changeCount != snapshot {
            foregroundAppIDs.formUnion(candidateAppIDs)
        } else if let item {
            ClipboardStore.shared.add(item)
        }
    }
}
