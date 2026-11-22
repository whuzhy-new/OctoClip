import SwiftUI
import Carbon
import UniformTypeIdentifiers

struct SettingsView: View {
    private struct HistoryCleanup {
        let days: Int
        let limit: Int
        let removalCount: Int
    }

    @ObservedObject var store: ClipboardStore
    @ObservedObject private var monitor = ClipboardMonitor.shared
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @ObservedObject private var sync = FavoriteSync.shared
    @State private var retentionDays: Int
    @State private var maxItems: Int
    @State private var pendingCleanup: HistoryCleanup?
    @State private var message: String?

    let onDismiss: () -> Void

    init(store: ClipboardStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
        _retentionDays = State(initialValue: store.retentionDays)
        _maxItems = State(initialValue: store.maxItems)
    }

    private var retentionSelection: Binding<Int> {
        Binding(get: { pendingCleanup?.days ?? retentionDays },
                set: { applyHistorySettings(days: $0, limit: maxItems) })
    }

    private var limitSelection: Binding<Int> {
        Binding(get: { pendingCleanup?.limit ?? maxItems },
                set: { applyHistorySettings(days: retentionDays, limit: $0) })
    }

    private var confirmingCleanup: Binding<Bool> {
        Binding(get: { pendingCleanup != nil }, set: { if !$0 { pendingCleanup = nil } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PanelStyle.gap) {
            PanelGlassGroup {
                HStack(spacing: PanelStyle.gap) {
                    PanelIconButton(symbol: .chevronLeft, label: "返回剪贴板", action: onDismiss)
                    Text("设置").font(PanelStyle.titleFont)
                    Spacer()
                }
            }

            ScrollView {
                VStack(spacing: PanelStyle.gap) {
                    settingGroup {
                        setting("保留时间", symbol: .clock) {
                            Picker("保留时间", selection: retentionSelection) {
                                ForEach(RetentionOption.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        setting("历史条数上限", symbol: .listOrdered) {
                            Picker("历史条数上限", selection: limitSelection) {
                                ForEach(MaxItemsOption.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    settingGroup {
                        setting("唤起快捷键", symbol: .keyboard) { shortcutControls }
                        setting("不记录的应用", symbol: .hand) { exclusionControls }
                        setting("收藏同步", symbol: .refresh) { syncControls }
                    }
                    if let message = message ?? sync.message ?? (hotkeys.registrationFailed ? "原快捷键无法注册，当前可连按两次 Shift。" : nil) {
                        Label {
                            Text(message)
                        } icon: {
                            LucideGlyph(.circleExclamation, size: PanelStyle.controlIconSize)
                                .accessibilityHidden(true)
                        }
                        .font(PanelStyle.controlFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(PanelStyle.smallGap)
            }
        }
        .onDisappear { hotkeys.stopRecording() }
        .alert("应用新的历史保留规则？", isPresented: confirmingCleanup, presenting: pendingCleanup) { cleanup in
            Button("取消", role: .cancel) {}
            Button("应用并清理", role: .destructive) {
                let latest = store.settingsRemovalCount(days: cleanup.days, limit: cleanup.limit)
                if latest > cleanup.removalCount {
                    DispatchQueue.main.async {
                        applyHistorySettings(days: cleanup.days, limit: cleanup.limit)
                    }
                } else {
                    saveHistorySettings(days: cleanup.days, limit: cleanup.limit)
                }
            }
        } message: { cleanup in
            Text("将删除 \(cleanup.removalCount) 条历史记录，收藏会保留。")
        }
    }

    private var shortcutControls: some View {
        HStack(spacing: PanelStyle.smallGap) {
            Button(hotkeys.isRecording ? "按下组合键…" : hotkeys.shortcutLabel) {
                if hotkeys.isRecording {
                    hotkeys.stopRecording()
                    return
                }
                message = nil
                hotkeys.beginRecording { event in
                    if Int(event.keyCode) == kVK_Escape {
                        hotkeys.stopRecording()
                    } else if let value = LaunchShortcut(event: event) {
                        if hotkeys.setShortcut(value) {
                            message = nil
                            hotkeys.stopRecording()
                        } else {
                            message = "这个组合键无法注册，请换一个。"
                        }
                    } else {
                        message = "请使用 ⌘、⌥ 或 ⌃ 搭配字符键。"
                    }
                }
            }
            .help("录入唤起快捷键")
            .accessibilityLabel(hotkeys.isRecording ? "正在录入快捷键" : "修改快捷键，当前为\(hotkeys.shortcutLabel)")
            if hotkeys.shortcut != nil || hotkeys.registrationFailed {
                Button("恢复默认") {
                    hotkeys.stopRecording()
                    hotkeys.setShortcut(nil)
                    message = nil
                }
            }
        }
    }

    private var exclusionControls: some View {
        Menu {
            Button("添加应用…", action: addExcludedApp)
            if !monitor.excludedApps.isEmpty { Divider() }
            ForEach(monitor.excludedApps, id: \.bundleID) { app in
                Button("重新记录 \(app.name)") { monitor.includeApplication(app.bundleID) }
            }
        } label: {
            Text(monitor.excludedApps.isEmpty ? "添加应用…" : "\(monitor.excludedApps.count) 个应用")
        }
        .accessibilityLabel("管理不记录的应用")
    }

    private var syncControls: some View {
        HStack(spacing: PanelStyle.smallGap) {
            if let folder = sync.folder {
                Text(folder.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: PanelStyle.settingsValueWidth)
                    .help(folder.path)
                Menu {
                    Button("刷新收藏", action: sync.refresh)
                    Button("断开并移除本机共享副本", action: sync.disconnect)
                } label: {
                    LucideGlyph(.circleEllipsis, size: PanelStyle.controlIconSize)
                }
                .accessibilityLabel("管理收藏同步")
                .disabled(sync.isWorking)
            } else {
                Button("选择文件夹…", action: chooseSyncFolder)
            }
        }
    }

    private func addExcludedApp() {
        let dialog = NSOpenPanel()
        dialog.title = "选择不记录的应用"
        dialog.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        dialog.allowedContentTypes = [.applicationBundle]
        dialog.allowsMultipleSelection = true
        PopupWindowController.shared.presentFilePanel(dialog) { _ in
            let success = dialog.urls.map { monitor.excludeApplication(at: $0) }.allSatisfy { $0 }
            message = success ? nil : "部分应用无法识别，请选择有效的应用。"
        }
    }

    private func chooseSyncFolder() {
        let dialog = NSOpenPanel()
        dialog.title = "选择收藏同步文件夹"
        dialog.message = "在不同 Mac 上选择同一个 iCloud Drive 或共享文件夹。只有手动开启同步的文本和图片会共享。"
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.canCreateDirectories = true
        PopupWindowController.shared.presentFilePanel(dialog) { url in
            message = nil
            sync.connect(url)
        }
    }

    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.vertical, PanelStyle.segmentInset)
            .panelTray()
    }

    private func setting<Control: View>(_ title: String, symbol: LucideIcon, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: PanelStyle.gap) {
            LucideGlyph(symbol)
                .foregroundStyle(PanelStyle.selection)
                .frame(width: PanelStyle.settingsIconSize, height: PanelStyle.settingsIconSize)
                .accessibilityHidden(true)
            Text(title).font(PanelStyle.bodyFont)
            Spacer()
            control().fixedSize()
        }
        .frame(minHeight: PanelStyle.settingsRowHeight)
        .padding(.horizontal, PanelStyle.horizontalInset)
    }

    private func applyHistorySettings(days: Int, limit: Int) {
        guard days != retentionDays || limit != maxItems else { return }
        let removalCount = store.settingsRemovalCount(days: days, limit: limit)
        if removalCount > 0 {
            pendingCleanup = HistoryCleanup(days: days, limit: limit, removalCount: removalCount)
        } else {
            saveHistorySettings(days: days, limit: limit)
        }
    }

    private func saveHistorySettings(days: Int, limit: Int) {
        store.saveSettings(days: days, limit: limit)
        retentionDays = days
        maxItems = limit
    }
}
