import SwiftUI
import UniformTypeIdentifiers

private enum TimeFilter: String, CaseIterable {
    case all = "全部"
    case today = "今天"
    case yesterday = "昨天"
    case threeDays = "近 3 天"

    func contains(_ date: Date, calendar: Calendar, now: Date) -> Bool {
        switch self {
        case .all: return true
        case .today: return calendar.isDateInToday(date)
        case .yesterday: return calendar.isDateInYesterday(date)
        case .threeDays:
            return calendar.date(byAdding: .day, value: -3, to: now).map { date >= $0 } ?? false
        }
    }
}

private enum TypeFilter: String, CaseIterable {
    case all = "全部"
    case text = "文本"
    case image = "图片"
    case file = "文件"

    var itemType: ClipboardItemType? {
        switch self {
        case .all: return nil
        case .text: return .text
        case .image: return .image
        case .file: return .file
        }
    }
}

private enum ViewMode: String {
    case list, grid
}

struct PopupView: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject private var window = PopupWindowController.shared
    @ObservedObject private var pasteService = PasteService.shared
    @ObservedObject private var pasteQueue = PasteQueue.shared
    @ObservedObject private var sync = FavoriteSync.shared
    @StateObject private var imageText = ImageTextIndex()
    @FocusState private var keyboardFocus: FocusTarget?
    @AppStorage("viewMode") private var viewMode: ViewMode = .list
    @State private var searchText = ""
    @State private var selectedItemID: UUID?
    @State private var hoveredItemID: UUID?
    @State private var cleanup: Cleanup?
    @State private var timeFilter: TimeFilter = .all
    @State private var typeFilter: TypeFilter = .all
    @State private var showingTimeFilter = false
    @State private var sourceFilter: String?
    @State private var favoriteGroup: String?
    @State private var editor: ClipEditorRequest?
    @State private var pendingTemplatePaste: (clip: ClipboardItem, queued: PasteQueue.Entry?)?
    @State private var batchMode = false
    @State private var batchIDs: [UUID] = []
    @State private var reviewingBatch = false
    @State private var fileOperationInProgress = false
    @State private var pendingImageCopy: (id: UUID, pasteboardChange: Int, presentation: Int)?

    private struct Cleanup: Identifiable {
        let id = UUID()
        let title: String
        let items: Set<UUID>
    }

    private enum FocusTarget: Hashable {
        case search
        case result(UUID)
    }

    private static let scopes = [
        PanelSegment(choice: false, title: "历史", symbol: .clock),
        PanelSegment(choice: true, title: "收藏", symbol: .star)
    ]
    private static let types = TypeFilter.allCases.map {
        PanelSegment(choice: $0, title: $0.rawValue)
    }
    private static let layouts = [
        PanelSegment(choice: ViewMode.list, title: "列表视图", symbol: .list),
        PanelSegment(choice: ViewMode.grid, title: "宫格视图", symbol: .grid)
    ]
    private static let gridColumns = [GridItem(.adaptive(minimum: PanelStyle.gridMinimumWidth), spacing: PanelStyle.gap)]

    private var sourceItems: [ClipboardItem] {
        guard store.showingFavorites else { return store.items }
        return allFavorites.filter { favoriteGroup == nil || $0.group == favoriteGroup }
    }

    private var allFavorites: [ClipboardItem] {
        let localIDs = Set(store.favoriteItems.map(\.id))
        return (store.favoriteItems + sync.incoming.filter { !localIDs.contains($0.id) })
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var groups: [String] {
        Array(Set(allFavorites.compactMap(\.group))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var sourceApps: [ClipSource] {
        var seen: Set<String> = []
        return sourceItems.compactMap(\.source).filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var activeSourceName: String? {
        sourceFilter.map { id in sourceApps.first(where: { $0.bundleID == id })?.name ?? id }
    }

    private var filterLabel: String {
        var parts = ["时间和来源筛选"]
        if timeFilter != .all { parts.append(timeFilter.rawValue) }
        if let activeSourceName { parts.append(activeSourceName) }
        return parts.joined(separator: "，")
    }

    private var selectedClips: [ClipboardItem] {
        guard !batchIDs.isEmpty else { return [] }
        let entries = store.showingFavorites ? allFavorites : store.items
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return batchIDs.compactMap { byID[$0] }
    }

    private var isSearchingImages: Bool {
        imageText.indexing && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            sourceItems.contains { $0.supportsTextRecognition && imageText.results[$0.id] == nil && passesFilters($0) }
    }

    private func passesFilters(_ item: ClipboardItem, now: Date = Date()) -> Bool {
        (typeFilter.itemType == nil || typeFilter.itemType == item.type) &&
            (sourceFilter == nil || sourceFilter == item.source?.bundleID) &&
            timeFilter.contains(item.timestamp, calendar: .current, now: now)
    }

    private var filteredItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        return sourceItems.filter { item in
            passesFilters(item, now: now) && (query.isEmpty || item.matchesSearch(query) ||
                imageText.results[item.id]?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private var displayedItems: [ClipboardItem] {
        reviewingBatch ? selectedClips : filteredItems
    }

    var body: some View {
        PanelShell {
            if window.destination == .settings {
                SettingsView(store: store, onDismiss: { window.destination = .clipboard })
            } else {
                let items = filteredItems
                VStack(spacing: PanelStyle.gap) {
                    header
                    results(reviewingBatch ? selectedClips : items)
                    notices
                    footer(filtered: items)
                }
                .disabled(pasteService.isPasting)
                .alert(item: $cleanup) { request in
                    Alert(
                        title: Text(request.title),
                        message: Text("将删除 \(request.items.count) 条历史记录，收藏会保留。"),
                        primaryButton: .cancel(Text("取消")),
                        secondaryButton: .destructive(Text("删除")) {
                            store.deleteHistory(ids: request.items)
                            focusSearch()
                        }
                    )
                }
            }
        }
        .onAppear {
            window.handleKeyCommand = handleKeyCommand
            updateTextIndex()
            focusSearch()
        }
        .onDisappear { window.handleKeyCommand = nil }
        .onChange(of: window.presentation) { _ in focusSearch() }
        .onChange(of: window.destination) { _ in
            showingTimeFilter = false
            focusSearch()
        }
        .onChange(of: store.showingFavorites) { _ in
            clearBatch()
            sourceFilter = nil
            resetSelection()
        }
        .onChange(of: typeFilter) { _ in filtersDidChange() }
        .onChange(of: timeFilter) { _ in filtersDidChange() }
        .onChange(of: sourceFilter) { _ in filtersDidChange() }
        .onChange(of: favoriteGroup) { _ in
            if let sourceFilter, !sourceApps.contains(where: { $0.bundleID == sourceFilter }) {
                self.sourceFilter = nil
            }
            filtersDidChange()
        }
        .onChange(of: keyboardFocus) { focus in
            if case .result(let id)? = focus { selectedItemID = id }
        }
        .onChange(of: selectedClips.isEmpty) { empty in
            if empty && reviewingBatch { closeSelectedReview() }
        }
        .onChange(of: groups) { names in
            if let favoriteGroup, !names.contains(favoriteGroup) { self.favoriteGroup = nil }
        }
        .onChange(of: viewMode) { _ in hoveredItemID = nil }
        .onReceive(store.$items) { _ in DispatchQueue.main.async { updateTextIndex() } }
        .onReceive(store.$favoriteItems) { _ in DispatchQueue.main.async { updateTextIndex() } }
        .onReceive(sync.$incoming) { _ in DispatchQueue.main.async { updateTextIndex() } }
        .onReceive(imageText.$results) { results in
            if let pending = pendingImageCopy, let text = results[pending.id] {
                DispatchQueue.main.async { finishImageCopy(pending.id, text: text) }
            }
        }
        .sheet(item: $editor, onDismiss: editorDidDismiss) { request in
            ClipEditor(request: request, groups: groups) { edited in
                commitEdit(edited, request: request)
            } onCancel: {
                editor = nil
            }
        }
    }

    private var header: some View {
        VStack(spacing: PanelStyle.gap) {
            searchField
            toolbar
                .padding(.horizontal, PanelStyle.segmentInset)
        }
    }

    private var headerSeparator: some View {
        Rectangle()
            .fill(contrast == .increased ? PanelStyle.border : PanelStyle.separator)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var searchField: some View {
        let shape = RoundedRectangle(cornerRadius: PanelStyle.searchCorner, style: .continuous)
        return HStack(spacing: PanelStyle.gap) {
            LucideGlyph(.search)
                .foregroundStyle(PanelStyle.muted)
                .accessibilityHidden(true)
            TextField("搜索剪贴板", text: $searchText,
                      prompt: Text("搜索剪贴板…").foregroundColor(PanelStyle.muted))
                .textFieldStyle(.plain)
                .font(PanelStyle.searchFont)
                .focused($keyboardFocus, equals: .search)
                .onChange(of: searchText) { _ in filtersDidChange() }
                .onSubmit {
                    if let item = selectedItem(in: displayedItems) { activate(item) }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    focusSearch()
                } label: {
                    LucideGlyph(.circleX)
                        .foregroundStyle(PanelStyle.muted)
                        .frame(width: PanelStyle.toolHeight, height: PanelStyle.toolHeight)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
                .help("清除搜索")
            }
            if store.showingFavorites && !groups.isEmpty {
                favoriteGroupMenu
                    .padding(.leading, PanelStyle.smallGap)
            }
        }
        .padding(.leading, PanelStyle.itemInset)
        .padding(.trailing, PanelStyle.smallGap)
        .frame(height: PanelStyle.searchHeight)
        .background(PanelStyle.searchSurface.opacity(PanelStyle.searchFillOpacity), in: shape)
        .panelGlass(in: shape)
        .clipShape(shape)
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(PanelStyle.border, lineWidth: PanelStyle.outlineWidth)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if #available(macOS 13, *) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PanelStyle.gap) {
                    browseControls.frame(maxWidth: .infinity, alignment: .leading)
                    tools
                }
                stackedToolbar
            }
        } else {
            stackedToolbar
        }
    }

    private var stackedToolbar: some View {
        VStack(alignment: .leading, spacing: PanelStyle.gap) {
            browseControls
            tools
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var browseControls: some View {
        HStack(spacing: PanelStyle.smallGap) {
            PanelSegments(label: "浏览范围", options: Self.scopes, selection: $store.showingFavorites)
            headerSeparator
                .frame(width: PanelStyle.outlineWidth, height: PanelStyle.toolbarSeparatorHeight)
            PanelSegments(label: "类型筛选", options: Self.types, selection: $typeFilter)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tools: some View {
        HStack(spacing: PanelStyle.segmentInset) {
            PanelSegments(label: "显示方式", options: Self.layouts, selection: $viewMode, iconsOnly: true)
            batchButton
                .disabled(sourceItems.isEmpty && !batchMode)
                .padding(.leading, PanelStyle.smallGap)
            PanelIconButton(
                symbol: .calendarDays,
                label: filterLabel,
                active: timeFilter != .all || sourceFilter != nil || showingTimeFilter,
                visibleTitle: activeSourceName ?? (timeFilter == .all ? nil : timeFilter.rawValue),
                grouped: true
            ) {
                showingTimeFilter.toggle()
            }
            .popover(isPresented: $showingTimeFilter, arrowEdge: .top) { timeFilterPopover }
            .onChange(of: showingTimeFilter) { visible in
                if !visible { focusSearch() }
            }
            if store.showingFavorites { favoriteActions }
            else { cleanupMenu }
            PanelIconButton(symbol: .settings, label: "设置", grouped: true) {
                window.destination = .settings
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var batchButton: some View {
        let title = batchMode ? "退出多选" : "多选"
        return PanelIconButton(symbol: .circleCheck, label: title, active: batchMode,
                               visibleTitle: title, grouped: true, action: toggleBatchMode)
    }

    private var timeFilterPopover: some View {
        VStack(alignment: .leading, spacing: PanelStyle.sectionGap) {
            VStack(alignment: .leading, spacing: PanelStyle.smallGap) {
                Text("时间").font(PanelStyle.controlFont)
                Picker("时间", selection: $timeFilter) {
                    ForEach(TimeFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            if !sourceApps.isEmpty || sourceFilter != nil {
                Picker("来源应用", selection: $sourceFilter) {
                    Text("所有应用").tag(String?.none)
                    ForEach(sourceApps, id: \.bundleID) { app in
                        Text(app.name).tag(Optional(app.bundleID))
                    }
                    if let sourceFilter, !sourceApps.contains(where: { $0.bundleID == sourceFilter }) {
                        Text(sourceFilter).tag(Optional(sourceFilter))
                    }
                }
            }
            HStack {
                Spacer()
                PanelPrimaryButton(title: "完成") { showingTimeFilter = false }
            }
        }
        .padding(PanelStyle.horizontalInset)
        .fixedSize(horizontal: true, vertical: false)
        .tint(PanelStyle.selection)
    }

    private var cleanupMenu: some View {
        toolbarMenu(label: "历史操作") {
            Button("清空历史") {
                requestCleanup(title: "清空历史？", items: Set(store.items.map(\.id)))
            }
            .disabled(store.items.isEmpty)
            Divider()
            ForEach([1, 3, 7], id: \.self) { days in
                let ids = store.expirationIDs(days: days)
                Button("删除 \(days) 天前的历史") {
                    requestCleanup(title: "删除 \(days) 天前的历史？", items: ids)
                }
                .disabled(ids.isEmpty)
            }
        }
    }

    private var favoriteGroupMenu: some View {
        Menu {
            Picker("收藏分组", selection: $favoriteGroup) {
                Text("全部收藏").tag(String?.none)
                ForEach(groups, id: \.self) { group in Text(group).tag(Optional(group)) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(favoriteGroup ?? "全部收藏")
                .font(PanelStyle.controlFont)
                .lineLimit(1)
                .frame(maxWidth: PanelStyle.searchScopeWidth, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, PanelStyle.smallGap)
        .accessibilityLabel("收藏分组，\(favoriteGroup ?? "全部收藏")")
    }

    private var favoriteActions: some View {
        toolbarMenu(label: "收藏操作") {
            Button("新建片段…") { editor = .create(group: favoriteGroup) }
            Divider()
            Button("导出本机收藏…") { exportFavorites() }
                .disabled(store.favoriteItems.isEmpty || fileOperationInProgress)
            Button("导入收藏…") { importFavorites() }
                .disabled(fileOperationInProgress)
        }
    }

    private func toolbarMenu<Content: View>(label: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            Color.clear
                .frame(width: PanelStyle.toolWidth, height: PanelStyle.segmentHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: PanelStyle.toolWidth, height: PanelStyle.segmentHeight)
        // Draw the glyph in SwiftUI so it uses the panel's adaptive text color.
        .overlay {
            LucideGlyph(.ellipsis)
                .foregroundStyle(PanelStyle.text)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(label)
        .help(label)
    }

    private func focusSearch() {
        guard window.destination == .clipboard, editor == nil else { return }
        keyboardFocus = nil
        DispatchQueue.main.async {
            if window.destination == .clipboard && !showingTimeFilter && editor == nil { keyboardFocus = .search }
        }
    }

    private func selectedItem(in items: [ClipboardItem]) -> ClipboardItem? {
        items.first { $0.id == selectedItemID } ?? items.first
    }

    private func handleKeyCommand(_ command: PopupWindowController.KeyCommand) -> Bool {
        switch command {
        case .escape:
            if cleanup != nil {
                cleanup = nil
                focusSearch()
            } else if showingTimeFilter {
                showingTimeFilter = false
            } else if window.destination == .settings {
                window.destination = .clipboard
            } else if reviewingBatch {
                closeSelectedReview()
            } else if batchMode {
                clearBatch()
                focusSearch()
            } else {
                return false
            }
        case .move(let offset):
            guard window.destination == .clipboard, !showingTimeFilter, cleanup == nil,
                  !pasteService.isPasting, keyboardFocus == .search, editor == nil else { return false }
            let items = displayedItems
            guard !items.isEmpty else { return false }
            let current = items.firstIndex { $0.id == selectedItemID } ?? items.startIndex
            let next = min(max(current + offset, 0), items.count - 1)
            if next != current { pasteService.clearFeedback() }
            selectedItemID = items[next].id
        case .pasteNext:
            guard window.destination == .clipboard, !showingTimeFilter, cleanup == nil,
                  !pasteService.isPasting, editor == nil else { return false }
            pasteNextInQueue()
        case .preview, .spacePreview, .pasteIndex, .plainPaste:
            guard window.destination == .clipboard, !showingTimeFilter, cleanup == nil,
                  !pasteService.isPasting, editor == nil else { return false }
            let items = displayedItems
            switch command {
            case .preview:
                guard let item = selectedItem(in: items) else { return false }
                preview(item)
            case .spacePreview:
                guard case .result(let id)? = keyboardFocus,
                      let item = items.first(where: { $0.id == id }) else { return false }
                preview(item)
            case .pasteIndex(let index):
                guard items.indices.contains(index), !batchMode else { return false }
                activate(items[index])
            case .plainPaste:
                guard let item = selectedItem(in: items), item.type == .text, !batchMode else { return false }
                paste(item, mode: .plainText)
            default: return false
            }
        }
        return true
    }

    private func activate(_ item: ClipboardItem) {
        if batchMode || NSApp.currentEvent?.modifierFlags.contains(.command) == true &&
            NSApp.currentEvent?.type == .leftMouseUp {
            toggleBatchItem(item)
        } else if !item.templateFields.isEmpty {
            editor = .fill(item)
        } else {
            paste(item)
        }
    }

    private func paste(_ item: ClipboardItem, mode: PasteMode = .original) {
        selectedItemID = item.id
        pasteService.pasteToFrontApp(item, mode: mode)
    }

    private func preview(_ item: ClipboardItem) {
        selectedItemID = item.id
        keyboardFocus = nil
        do {
            try window.showPreview(item, onClose: focusSearch)
        } catch {
            pasteService.report(item.type == .file ? "原文件已移动或无法访问。" : "无法打开快速查看。")
            focusSearch()
        }
    }

    private func commitEdit(_ clip: ClipboardItem, request: ClipEditorRequest) {
        switch request {
        case .fill(_, let queued):
            pendingTemplatePaste = (clip, queued)
        case .merge:
            pendingTemplatePaste = (clip, nil)
        case .metadata(_, let favorite):
            if favorite { store.saveFavorite(clip) }
            else { store.editMetadata(id: clip.id, name: clip.name, sourceURL: clip.sourceURL) }
        case .create:
            store.saveFavorite(clip)
        }
        editor = nil
    }

    private func editorDidDismiss() {
        if let pending = pendingTemplatePaste {
            pendingTemplatePaste = nil
            DispatchQueue.main.async {
                if let queued = pending.queued { pasteQueue.paste(queued, filled: pending.clip) }
                else { paste(pending.clip, mode: .plainText) }
            }
        } else {
            focusSearch()
        }
    }

    private func updateTextIndex() {
        imageText.update(store.items + store.favoriteItems + sync.incoming)
    }

    private func copyText(_ text: String, confirmation: String) {
        let copied = pasteService.copyToClipboard(.text(text), mode: .plainText)
        pasteService.report(copied ? confirmation : "无法写入剪贴板。")
    }

    private func copyImageText(_ item: ClipboardItem) {
        guard let text = imageText.results[item.id] else {
            pendingImageCopy = (item.id, NSPasteboard.general.changeCount, window.presentation)
            imageText.prioritize(item)
            pasteService.report("正在识别图中文字…")
            return
        }
        pendingImageCopy = nil
        copyRecognizedText(text)
    }

    private func finishImageCopy(_ id: UUID, text: String) {
        guard let pending = pendingImageCopy, pending.id == id else { return }
        pendingImageCopy = nil
        guard window.isVisible, window.presentation == pending.presentation, window.destination == .clipboard else { return }
        guard NSPasteboard.general.changeCount == pending.pasteboardChange else {
            pasteService.report("已识别文字，可从条目菜单复制。")
            return
        }
        copyRecognizedText(text)
    }

    private func copyRecognizedText(_ text: String) {
        guard !text.isEmpty else {
            pasteService.report("未识别到可复制的文字。")
            return
        }
        copyText(text, confirmation: "已复制图中文字。")
    }

    private func toggleBatchMode() {
        if batchMode { clearBatch() }
        else { batchMode = true }
        focusSearch()
    }

    private func clearBatch() {
        batchMode = false
        batchIDs = []
        reviewingBatch = false
    }

    private func closeSelectedReview() {
        reviewingBatch = false
        resetSelection()
        focusSearch()
    }

    private func toggleBatchItem(_ item: ClipboardItem) {
        batchMode = true
        if let index = batchIDs.firstIndex(of: item.id) {
            batchIDs.remove(at: index)
        } else {
            batchIDs.append(item.id)
            if item.supportsTextRecognition { imageText.prioritize(item) }
        }
        selectedItemID = item.id
        focusSearch()
    }

    private func beginQueue(_ clips: [ClipboardItem]) {
        pasteQueue.start(clips)
        clearBatch()
        pasteNextInQueue()
    }

    private func pasteNextInQueue() {
        guard let entry = pasteQueue.nextEntry, editor == nil else { return }
        if entry.item.templateFields.isEmpty {
            pasteQueue.paste(entry)
        } else {
            editor = .fill(entry.item, queued: entry)
        }
    }

    private func mergeAndPaste(_ clips: [ClipboardItem]) {
        if clips.contains(where: { !$0.templateFields.isEmpty }) {
            editor = .merge(clips)
        } else {
            paste(.text(ClipDocument.mergedText(clips)), mode: .plainText)
        }
    }

    private func exportFavorites() {
        let clips = store.favoriteItems
        saveDocument(filename: "OctoClip 收藏.json", type: .json, confirmation: "收藏已导出。") {
            try FavoriteArchive(clips).encode()
        }
    }

    private func saveDocument(filename: String, type: UTType, confirmation: String, data: @escaping () throws -> Data) {
        let dialog = NSSavePanel()
        dialog.nameFieldStringValue = filename
        dialog.allowedContentTypes = [type]
        window.presentFilePanel(dialog) { url in
            fileOperationInProgress = true
            DispatchQueue.global(qos: .userInitiated).async {
                let success: Bool
                do {
                    try data().write(to: url, options: .atomic)
                    success = true
                } catch {
                    success = false
                }
                DispatchQueue.main.async {
                    fileOperationInProgress = false
                    pasteService.report(success ? confirmation : "无法写入文件，请检查目标位置后重试。")
                }
            }
        }
    }

    private func importFavorites() {
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.json]
        window.presentFilePanel(dialog) { url in
            fileOperationInProgress = true
            DispatchQueue.global(qos: .userInitiated).async {
                let clips = try? FavoriteArchive.read(url)
                DispatchQueue.main.async {
                    fileOperationInProgress = false
                    if let clips {
                        let count = store.importFavorites(clips)
                        pasteService.report(count == 0 ? "这些收藏已存在。" : "已导入 \(count) 条收藏。")
                    } else {
                        pasteService.report("无法读取文件，请选择 OctoClip 导出的收藏。")
                    }
                }
            }
        }
    }

    private func resetSelection() {
        selectedItemID = nil
        pasteService.clearFeedback()
    }

    private func filtersDidChange() {
        reviewingBatch = false
        resetSelection()
    }

    private func resetFilters() {
        timeFilter = .all
        typeFilter = .all
        sourceFilter = nil
        resetSelection()
    }

    private func requestCleanup(title: String, items: Set<UUID>) {
        guard !items.isEmpty else { return }
        cleanup = Cleanup(title: title, items: items)
    }

    private func results(_ items: [ClipboardItem]) -> some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                let selection = selectedItem(in: items)?.id
                let quickKeys = quickKeys(for: items)
                ScrollViewReader { scroll in
                    ScrollView {
                        if viewMode == .list {
                            LazyVStack(spacing: PanelStyle.segmentInset) {
                                ForEach(items) { item in
                                    entry(item, selected: item.id == selection, quickKey: quickKeys[item.id])
                                }
                            }
                            .padding(.vertical, PanelStyle.segmentInset)
                        } else {
                            LazyVGrid(columns: Self.gridColumns, spacing: PanelStyle.gap) {
                                ForEach(items) { item in
                                    entry(item, selected: item.id == selection, quickKey: quickKeys[item.id])
                                }
                            }
                            .padding(PanelStyle.smallGap)
                        }
                    }
                    .onChange(of: selection) { id in
                        if let id { scroll.scrollTo(id) }
                    }
                    .onChange(of: viewMode) { _ in
                        if let selection { scroll.scrollTo(selection) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickKeys(for items: [ClipboardItem]) -> [UUID: Int] {
        guard window.commandHeld, !batchMode else { return [:] }
        return Dictionary(items.prefix(9).enumerated().map { ($0.element.id, $0.offset + 1) },
                          uniquingKeysWith: { first, _ in first })
    }

    private func entry(_ item: ClipboardItem, selected: Bool, quickKey: Int?) -> some View {
        let favorite = store.isFavorite(item)
        let hovered = hoveredItemID == item.id
        let shape = RoundedRectangle(cornerRadius: PanelStyle.itemCorner)
        let summary = item.type == .text && item.name == nil && viewMode == .list
            ? item.displayTitle.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            : item.displayTitle
        let checked = batchIDs.contains(item.id)
        let highlighted = selected || (batchMode && checked)
        let fill = entryColor(highlighted: highlighted, hovered: hovered)
        return HStack(spacing: 0) {
            Button { activate(item) } label: {
                HStack(spacing: 0) {
                    if batchMode {
                        LucideGlyph(checked ? .circleCheck : .circle)
                            .foregroundStyle(checked ? PanelStyle.selection : PanelStyle.muted)
                            .padding(.leading, PanelStyle.itemInset)
                            .accessibilityHidden(true)
                    }
                    if viewMode == .list {
                        ClipboardRow(item: item, title: summary, favorite: favorite)
                    } else {
                        ClipboardCard(item: item, favorite: favorite)
                    }
                }
            }
            .buttonStyle(.plain)
            .focused($keyboardFocus, equals: .result(item.id))
            .accessibilityLabel(item.source.map { "\(summary)，来源 \($0.name)" } ?? summary)
            .accessibilityValue(batchMode ? (checked ? "已选中" : "未选中") : (favorite ? "已收藏" : ""))
            .accessibilityAddTraits((batchMode ? checked : selected) ? .isSelected : [])
            .accessibilityHint(batchMode ? "切换条目选择" : "粘贴到原应用")

            if viewMode == .list && hovered && !batchMode && quickKey == nil {
                rowActions(item, favorite: favorite)
            }
        }
        .clipShape(shape)
        .background {
            if viewMode == .grid {
                shape.fill(fill)
                    .shadow(color: PanelStyle.cardShadow, radius: PanelStyle.cardShadowRadius,
                            y: PanelStyle.cardShadowOffset)
            } else {
                shape.fill(fill)
            }
        }
        .overlay {
            if keyboardFocus == .result(item.id) || (contrast == .increased && highlighted) {
                shape.strokeBorder(PanelStyle.selection, lineWidth: PanelStyle.selectionWidth)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let quickKey {
                Text("⌘\(quickKey)")
                    .font(PanelStyle.badgeFont)
                    .padding(PanelStyle.smallGap)
                    .background(PanelStyle.control, in: Capsule())
                    .padding(PanelStyle.smallGap)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onHover { entered in
            if entered { hoveredItemID = item.id }
            else if hoveredItemID == item.id { hoveredItemID = nil }
        }
        .contextMenu { itemContextMenu(for: item) }
        .id(item.id)
    }

    private func entryColor(highlighted: Bool, hovered: Bool) -> Color {
        if highlighted { return PanelStyle.selectedItem }
        if hovered { return PanelStyle.hover }
        return viewMode == .grid ? PanelStyle.card : .clear
    }

    private func rowActions(_ item: ClipboardItem, favorite: Bool) -> some View {
        HStack(spacing: PanelStyle.smallGap) {
            rowAction(favoriteActionTitle(favorite), symbol: favorite ? .starOff : .star) {
                store.toggleFavorite(item)
            }
            if item.type == .text {
                rowAction("纯文本粘贴", symbol: .type) { paste(item, mode: .plainText) }
            }
            rowAction("快速查看", symbol: .eye) { preview(item) }
        }
        .padding(.trailing, PanelStyle.smallGap)
    }

    private func favoriteActionTitle(_ favorite: Bool) -> String {
        if favorite { return "取消收藏" }
        return store.showingFavorites ? "存为本机收藏" : "收藏"
    }

    private func rowAction(_ label: String, symbol: LucideIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideGlyph(symbol, size: PanelStyle.controlIconSize)
                .foregroundStyle(PanelStyle.muted)
                .frame(width: PanelStyle.segmentHeight, height: PanelStyle.segmentHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private func itemContextMenu(for item: ClipboardItem) -> some View {
        Button("快速查看") { preview(item) }
        if item.template == true {
            Button("填写模板…") { activate(item) }
                .disabled(batchMode)
        }
        Button("原样粘贴") { paste(item) }
        if item.type == .text {
            Menu("转换后粘贴") {
                Button("纯文本") { paste(item, mode: .plainText) }
                Button("去换行") { paste(item, mode: .noNewlines) }
                Button("去首尾空白") { paste(item, mode: .trimmed) }
                Button("Markdown") { paste(item, mode: .markdown) }
            }
        } else if item.supportsTextRecognition {
            Button("复制图中文字") { copyImageText(item) }
        }
        Divider()
        Button(batchIDs.contains(item.id) ? "取消选择" : "加入多选") { toggleBatchItem(item) }
        let favorite = store.isFavorite(item)
        let received = store.showingFavorites && !favorite
        Button(favoriteActionTitle(favorite)) { store.toggleFavorite(item) }
        if !received {
            Button(store.showingFavorites ? "编辑收藏…" : "编辑条目…") {
                editor = .metadata(item, favorite: store.showingFavorites)
            }
        }
        if store.showingFavorites && favorite && sync.folder != nil && sync.canPublish(item) {
            Button(sync.selectedIDs.contains(item.id) ? "停止同步此收藏" : "同步此收藏") {
                sync.toggle(item)
            }
        }
        if !store.showingFavorites {
            Divider()
            Button("从历史删除", role: .destructive) { store.deleteHistoryItem(item) }
        }
    }

    private var emptyState: some View {
        let isFiltered = !sourceItems.isEmpty
        return VStack(spacing: PanelStyle.gap) {
            LucideGlyph(isFiltered ? .listFilter : (store.showingFavorites ? .star : .clipboard),
                        size: PanelStyle.emptyIconSize)
                .accessibilityHidden(true)
            if isSearchingImages {
                ProgressView("正在识别图片…").controlSize(.small)
            } else {
                Text(emptyMessage(filtered: isFiltered)).font(PanelStyle.bodyFont)
            }
            if isFiltered && !isSearchingImages {
                Button("清除筛选") {
                    searchText = ""
                    resetFilters()
                    focusSearch()
                }
            } else if store.showingFavorites && !store.items.isEmpty {
                Button("查看历史") { store.showingFavorites = false }
            }
        }
        .foregroundStyle(PanelStyle.muted)
        .padding(PanelStyle.panelInset)
    }

    private func emptyMessage(filtered: Bool) -> String {
        if filtered { return "当前筛选无结果" }
        if store.recoveryFile != nil { return "暂无可读取的记录" }
        return store.showingFavorites ? "暂无收藏" : "复制内容后会显示在这里"
    }

    @ViewBuilder
    private var notices: some View {
        if store.saveFailed || store.recoveryFile != nil || pasteService.feedback != nil ||
            store.undoTitle != nil || fileOperationInProgress || pasteQueue.manualPayload != nil ||
            (store.showingFavorites && sync.message != nil) {
            VStack(spacing: PanelStyle.smallGap) {
                if store.saveFailed {
                    notice("剪贴板记录保存失败。", symbol: .circleExclamation) {
                        Button("重试保存", action: store.retryPersistence)
                    }
                }
                if let recovery = store.recoveryFile {
                    notice("部分记录无法读取，原文件已保留。", symbol: .circleExclamation) {
                        if store.canRetryReading { Button("重试读取", action: store.retryPersistence) }
                        Button("查看原文件") { NSWorkspace.shared.activateFileViewerSelecting([recovery]) }
                    }
                }
                if let feedback = pasteService.feedback {
                    notice(feedback.message, symbol: feedback.canCopy ? .circleExclamation : .info) {
                        if feedback.canCopy { Button("复制到剪贴板", action: pasteService.copyFallback) }
                    }
                }
                if pasteQueue.manualPayload != nil {
                    notice("已复制当前条目。切回目标应用按 ⌘V。", symbol: .clipboard) {
                        Button("重新复制", action: pasteQueue.recopy)
                    }
                }
                if fileOperationInProgress {
                    notice("正在处理文件…", symbol: .file) { ProgressView().controlSize(.small) }
                }
                if store.showingFavorites, let message = sync.message {
                    notice(message, symbol: .refresh) {
                        if sync.folder != nil {
                            Button("重试", action: sync.refresh)
                        }
                    }
                }
                if let undo = store.undoTitle {
                    notice(undo, symbol: .undo) {
                        Button("撤销", action: store.undoDeletion)
                    }
                }
            }
        }
    }

    private func notice<Actions: View>(_ message: String, symbol: LucideIcon, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: PanelStyle.gap) {
            Label {
                Text(message)
            } icon: {
                LucideGlyph(symbol, size: PanelStyle.controlIconSize)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(PanelStyle.text)
            Spacer(minLength: 0)
            actions()
        }
        .font(PanelStyle.controlFont)
        .controlSize(.small)
        .padding(.horizontal, PanelStyle.itemInset)
        .padding(.vertical, PanelStyle.smallGap)
        .background(PanelStyle.tray, in: RoundedRectangle(cornerRadius: PanelStyle.itemCorner))
    }

    private func footer(filtered items: [ClipboardItem]) -> some View {
        let count = items.count
        return HStack(spacing: PanelStyle.gap) {
            if batchMode {
                batchActions(filtered: items)
            } else {
                Text("\(count) 条").monospacedDigit()
                Spacer()
                if !pasteQueue.items.isEmpty {
                    if pasteQueue.manualPayload != nil {
                        Button("已粘贴，继续", action: pasteQueue.confirmManualPaste)
                    } else {
                        Button("粘贴下一条（\(pasteQueue.items.count)）", action: pasteNextInQueue)
                    }
                    Button("清空队列", action: pasteQueue.clear)
                } else if count > 0 {
                    if isSearchingImages { ProgressView().controlSize(.small).accessibilityLabel("正在识别图片") }
                    shortcut("⌘Y", "预览")
                    shortcut("↵", "粘贴")
                }
            }
        }
        .font(PanelStyle.metadataFont)
        .foregroundStyle(PanelStyle.muted)
        .padding(.horizontal, PanelStyle.smallGap)
    }

    private func batchActions(filtered items: [ClipboardItem]) -> some View {
        let clips = selectedClips
        let visibleIDs = Set(items.map(\.id))
        let hiddenCount = clips.filter { !visibleIDs.contains($0.id) }.count
        let ocrPending = clips.contains { $0.supportsTextRecognition && imageText.results[$0.id] == nil }
        return Group {
            if reviewingBatch {
                Text("已选 \(clips.count) 条").monospacedDigit()
                Button("返回结果", action: closeSelectedReview)
            } else if hiddenCount > 0 {
                Text("已选 \(clips.count) 条，含 \(hiddenCount) 条隐藏项").monospacedDigit()
                Button("查看已选") {
                    reviewingBatch = true
                    resetSelection()
                    focusSearch()
                }
            } else {
                Text("已选 \(clips.count) 条").monospacedDigit()
            }
            Spacer()
            if ocrPending { ProgressView().controlSize(.small).accessibilityLabel("正在识别所选图片") }
            Menu("批量操作") {
                Button(clips.contains { !$0.templateFields.isEmpty } ? "填写模板并合并粘贴…" : "合并为文本并粘贴") {
                    mergeAndPaste(clips)
                }
                .disabled(clips.count < 2 || clips.contains { $0.type != .text })
                Button(pasteQueue.items.isEmpty ? "按顺序逐条粘贴" : "替换队列并逐条粘贴") { beginQueue(clips) }
                Divider()
                Button("复制 Markdown 资料清单") {
                    copyText(ClipDocument.markdownList(clips, recognizedText: imageText.results), confirmation: "已复制资料清单。")
                }
                .disabled(ocrPending)
                Button("导出 Markdown 资料清单…") {
                    let markdown = ClipDocument.markdownList(clips, recognizedText: imageText.results)
                    saveDocument(filename: "剪贴资料.md", type: UTType(filenameExtension: "md") ?? .plainText,
                                 confirmation: "资料清单已导出。") { Data(markdown.utf8) }
                }
                .disabled(ocrPending || fileOperationInProgress)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(clips.isEmpty)
        }
    }

    private func shortcut(_ key: String, _ action: String) -> some View {
        HStack(spacing: PanelStyle.smallGap) {
            Text(key)
                .font(PanelStyle.badgeFont)
            Text(action)
        }
        .accessibilityElement(children: .combine)
    }
}
