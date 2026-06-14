import SwiftUI

// MARK: - Design Tokens

enum DS {
    // 主色
    static let accent = Color(nsColor: NSColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1.0)) // Indigo
    static let accentLight = Color(nsColor: NSColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 0.08))
    static let accentMid = Color(nsColor: NSColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 0.15))

    // 类型色标
    static let textColor = Color(nsColor: NSColor(red: 0.30, green: 0.36, blue: 0.80, alpha: 1.0))
    static let textBg = Color(nsColor: NSColor(red: 0.30, green: 0.36, blue: 0.80, alpha: 0.07))
    static let imageColor = Color(nsColor: NSColor(red: 0.16, green: 0.60, blue: 0.56, alpha: 1.0))
    static let imageBg = Color(nsColor: NSColor(red: 0.16, green: 0.60, blue: 0.56, alpha: 0.07))
    static let fileColor = Color(nsColor: NSColor(red: 0.80, green: 0.58, blue: 0.20, alpha: 1.0))
    static let fileBg = Color(nsColor: NSColor(red: 0.80, green: 0.58, blue: 0.20, alpha: 0.07))

    // 背景 & 表面
    static let bg = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceHover = Color(nsColor: NSColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 0.05))

    // 文字
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    // 其他
    static let divider = Color(nsColor: .separatorColor).opacity(0.5)
    static let favorite = Color(nsColor: NSColor(red: 0.95, green: 0.68, blue: 0.20, alpha: 1.0))

    // 尺寸
    static let cornerRadius: CGFloat = 12
    static let cardRadius: CGFloat = 8
}

// MARK: - 筛选枚举

enum TimeFilter: String, CaseIterable {
    case all = "全部"
    case today = "今天"
    case yesterday = "昨天"
    case threeDays = "近3天"
}

enum TypeFilter: String, CaseIterable {
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

enum ViewMode: String {
    case list
    case grid
}

// MARK: - PopupView

struct PopupView: View {
    @ObservedObject var store = ClipboardStore.shared
    @State private var searchText = ""
    @State private var hoveredItemID: UUID? = nil
    @State private var timeFilter: TimeFilter = .all
    @State private var typeFilter: TypeFilter = .all
    @State private var showingSettings = false
    @State private var viewMode: ViewMode = {
        let saved = UserDefaults.standard.string(forKey: "viewMode") ?? "list"
        return ViewMode(rawValue: saved) ?? .list
    }()

    var filteredItems: [ClipboardItem] {
        let source = store.showingFavorites ? store.favoriteItems : store.items
        return source.filter { item in
            let matchSearch = searchText.isEmpty ||
                item.preview.localizedCaseInsensitiveContains(searchText)
            let matchType = typeFilter == .all || item.type == typeFilter.itemType
            let matchTime: Bool = {
                switch timeFilter {
                case .all: return true
                case .today:
                    return Calendar.current.isDateInToday(item.timestamp)
                case .yesterday:
                    return Calendar.current.isDateInYesterday(item.timestamp)
                case .threeDays:
                    let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                    return item.timestamp >= cutoff
                }
            }()
            return matchSearch && matchType && matchTime
        }
    }

    var body: some View {
        if showingSettings {
            SettingsView(onDismiss: { showingSettings = false })
                .frame(width: 620, height: 480)
        } else {
            VStack(spacing: 0) {
                headerBar
                searchBar
                filterBar
                if viewMode == .list {
                    listContent
                } else {
                    gridContent
                }
                footer
            }
            .background(DS.bg)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
    }

    // MARK: - 顶部栏

    private var headerBar: some View {
        HStack(spacing: 0) {
            // Tab 切换
            HStack(spacing: 2) {
                tabPill(title: "历史", icon: "clock.arrow.circlepath", active: !store.showingFavorites) {
                    store.showingFavorites = false
                }
                tabPill(title: "收藏", icon: "star", active: store.showingFavorites) {
                    store.showingFavorites = true
                }
            }

            Spacer()

            // 设置
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textTertiary)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("设置")

            // 视图切换
            HStack(spacing: 1) {
                viewToggle(icon: "list.bullet", mode: .list)
                viewToggle(icon: "square.grid.2x2", mode: .grid)
            }
            .padding(2)
            .background(DS.accentLight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func tabPill(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .foregroundColor(active ? DS.accent : DS.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(active ? DS.accentLight : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func viewToggle(icon: String, mode: ViewMode) -> some View {
        Button {
            viewMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: "viewMode")
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(viewMode == mode ? DS.accent : DS.textTertiary)
                .frame(width: 26, height: 24)
                .background(viewMode == mode ? DS.accentMid : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.textTertiary)

            TextField("搜索剪贴板内容…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 筛选栏

    private var filterBar: some View {
        HStack(spacing: 6) {
            // 时间筛选
            ForEach(TimeFilter.allCases, id: \.self) { t in
                chipButton(title: t.rawValue, active: timeFilter == t) {
                    timeFilter = t
                }
            }

            Rectangle()
                .fill(DS.divider)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 4)

            // 类型筛选
            ForEach(TypeFilter.allCases, id: \.self) { t in
                chipButton(title: t.rawValue, icon: typeIcon(t), active: typeFilter == t) {
                    typeFilter = t
                }
            }

            Spacer()

            // 清理菜单
            Menu {
                Button(action: { store.clear() }) {
                    Label("清空全部", systemImage: "trash")
                }
                Divider()
                Button("删除 1 天前") { store.purgeOlderThan(days: 1) }
                Button("删除 3 天前") { store.purgeOlderThan(days: 3) }
                Button("删除 7 天前") { store.purgeOlderThan(days: 7) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func chipButton(title: String, icon: String? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
            }
            .foregroundColor(active ? DS.accent : DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? DS.accentLight : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func typeIcon(_ t: TypeFilter) -> String? {
        switch t {
        case .all: return nil
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    // MARK: - 列表视图

    private var listContent: some View {
        Group {
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredItems, id: \.id) { item in
                            Button {
                                PasteService.shared.pasteToFrontApp(item, mode: .original)
                            } label: {
                                ItemRow(item: item, isHovered: hoveredItemID == item.id, isFavorite: store.isFavorite(item))
                            }
                            .buttonStyle(.plain)
                            .onHover { h in hoveredItemID = h ? item.id : nil }
                            .contextMenu { itemContextMenu(for: item) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 宫格视图

    private static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var gridContent: some View {
        Group {
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.gridColumns, spacing: 10) {
                        ForEach(filteredItems, id: \.id) { item in
                            Button {
                                PasteService.shared.pasteToFrontApp(item, mode: .original)
                            } label: {
                                GridCell(item: item, isHovered: hoveredItemID == item.id, isFavorite: store.isFavorite(item))
                                    .frame(height: 140)
                            }
                            .buttonStyle(.plain)
                            .onHover { h in hoveredItemID = h ? item.id : nil }
                            .contextMenu { itemContextMenu(for: item) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func itemContextMenu(for item: ClipboardItem) -> some View {
        Button("原样粘贴") {
            PasteService.shared.pasteToFrontApp(item, mode: .original)
        }
        if item.type == .text {
            Button("纯文本粘贴") {
                PasteService.shared.pasteToFrontApp(item, mode: .plainText)
            }
        }
        Divider()
        Button(store.isFavorite(item) ? "取消收藏" : "收藏") {
            store.toggleFavorite(item)
        }
        Divider()
        Button("删除") {
            store.remove(item)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.showingFavorites ? "star.slash" : "clipboard")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundColor(DS.textTertiary.opacity(0.6))
            Text(emptyText)
                .font(.system(size: 12))
                .foregroundColor(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyText: String {
        if store.showingFavorites { return "暂无收藏" }
        if !searchText.isEmpty { return "没有找到匹配内容" }
        return "剪贴板为空"
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 0) {
            Text("OctoClip")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(DS.textTertiary.opacity(0.6))

            Text(" · ")
                .foregroundColor(DS.textTertiary.opacity(0.3))

            Text("\(filteredItems.count) 条")
                .foregroundColor(DS.textTertiary)
            Spacer()
            HStack(spacing: 8) {
                shortcutHint("⇧⇧", "唤出")
                shortcutHint("ESC", "关闭")
            }
        }
        .font(.system(size: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.surface.opacity(0.5))
    }

    private func shortcutHint(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(DS.divider)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(desc)
        }
        .foregroundColor(DS.textTertiary)
    }
}

// MARK: - 列表行

struct ItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                if item.hasRichText {
                    RichTextPreviewView(item: item, maxHeight: 32)
                        .frame(height: 32)
                } else {
                    Text(item.preview)
                        .font(.system(size: 12.5))
                        .foregroundColor(DS.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                HStack(spacing: 6) {
                    Text(formatTime(item.timestamp))
                        .font(.system(size: 10.5))
                        .foregroundColor(DS.textTertiary)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(DS.favorite)
                    }
                    if item.hasRichText {
                        Text("富文本")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DS.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer(minLength: 0)

            if isHovered {
                HStack(spacing: 3) {
                    ActionBtn(icon: isFavorite ? "star.slash" : "star", color: DS.favorite) {
                        ClipboardStore.shared.toggleFavorite(item)
                    }
                    ActionBtn(icon: "doc.on.doc", color: DS.accent) {
                        PasteService.shared.pasteToFrontApp(item, mode: .original)
                    }
                    if item.type == .text {
                        ActionBtn(icon: "textformat", color: DS.accent) {
                            PasteService.shared.pasteToFrontApp(item, mode: .plainText)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius)
                .fill(isHovered ? DS.surfaceHover : Color.clear)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.type {
        case .text:
            RoundedRectangle(cornerRadius: 7)
                .fill(DS.textBg)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.textColor)
                )
        case .image:
            if let data = item.imageData {
                if item.imageFormat == .gif {
                    AnimatedImageView(data: data)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else if let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            } else {
                RoundedRectangle(cornerRadius: 7)
                    .fill(DS.imageBg)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.imageColor)
                    )
            }
        case .file:
            RoundedRectangle(cornerRadius: 7)
                .fill(DS.fileBg)
                .overlay(
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.fileColor)
                )
        }
    }

    private func formatTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - 宫格单元格

struct GridCell: View {
    let item: ClipboardItem
    let isHovered: Bool
    let isFavorite: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 内容区
            ZStack(alignment: .topTrailing) {
                contentPreview
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(DS.favorite)
                        .padding(5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // 底部信息
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 10.5))
                    .foregroundColor(DS.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(height: 26, alignment: .topLeading)

                Text(formatTime(item.timestamp))
                    .font(.system(size: 9.5))
                    .foregroundColor(DS.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.cardRadius)
                .stroke(isHovered ? DS.accent.opacity(0.4) : DS.divider, lineWidth: isHovered ? 1.5 : 0.5)
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.06 : 0.02), radius: isHovered ? 6 : 2, y: isHovered ? 2 : 1)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text:
            if item.hasRichText {
                RichTextPreviewView(item: item, maxHeight: 80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(item.plainText?.prefix(100) ?? "")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(DS.textSecondary.opacity(0.8))
                    .lineLimit(nil)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(DS.textBg.opacity(0.5))
            }
        case .image:
            if let data = item.imageData {
                if item.imageFormat == .gif {
                    AnimatedImageView(data: data)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                DS.imageBg
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(DS.imageColor.opacity(0.6))
                    )
            }
        case .file:
            DS.fileBg
                .overlay(
                    Image(systemName: "folder")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(DS.fileColor.opacity(0.6))
                )
        }
    }

    private func formatTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Action Button

struct ActionBtn: View {
    let icon: String
    var color: Color = DS.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 富文本预览

/// 条件滚动的 ScrollView：仅当 enabled 为 true 时处理滚轮事件，否则透传给父视图
class ConditionalScrollView: NSScrollView {
    var scrollEnabled = false
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if scrollEnabled {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
}

/// 当 item 带有 HTML/RTF 样式时，用 NSTextView 渲染带样式的预览
/// hover 500ms 后启用滚动并自动向下滚动，离开后复位到顶部
struct RichTextPreviewView: NSViewRepresentable {
    let item: ClipboardItem
    let maxHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ConditionalScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineFragmentPadding = 2
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize.zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        scrollView.onMouseEntered = { [weak scrollView] in
            context.coordinator.scheduleScrollEnable(scrollView)
        }
        scrollView.onMouseExited = { [weak scrollView] in
            context.coordinator.disableScrolling(scrollView)
        }

        context.coordinator.textView = textView

        configureText(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? NSTextView {
            configureText(textView)
        }
    }

    private func configureText(_ textView: NSTextView) {
        let attrString: NSAttributedString
        if let htmlData = item.htmlData,
           let html = NSAttributedString(html: htmlData, documentAttributes: nil) {
            attrString = html
        } else if let rtfData = item.rtfData,
                  let rtf = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            attrString = rtf
        } else {
            attrString = NSAttributedString(string: item.plainText ?? "")
        }

        // 限制展示长度，避免超长内容卡顿
        let maxLen = 500
        let displayStr: NSAttributedString
        if attrString.length > maxLen {
            displayStr = attrString.attributedSubstring(from: NSRange(location: 0, length: maxLen))
        } else {
            displayStr = attrString
        }

        textView.textStorage?.setAttributedString(displayStr)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        weak var textView: NSTextView?
        private var hoverTimer: Timer?
        private var autoScrollTimer: Timer?

        func scheduleScrollEnable(_ scrollView: ConditionalScrollView?) {
            hoverTimer?.invalidate()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self, weak scrollView] _ in
                guard let sv = scrollView else { return }
                self?.enableScrolling(sv)
            }
        }

        func disableScrolling(_ scrollView: ConditionalScrollView?) {
            hoverTimer?.invalidate()
            hoverTimer = nil
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
            scrollView?.scrollEnabled = false
            // 复位到顶部
            scrollView?.contentView.scroll(to: NSPoint(x: 0, y: 0))
        }

        private func enableScrolling(_ scrollView: ConditionalScrollView) {
            scrollView.scrollEnabled = true

            // 自动向下滚动
            autoScrollTimer?.invalidate()
            autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak scrollView] _ in
                guard let sv = scrollView else { return }
                let currentOffset = sv.contentView.bounds.origin.y
                let docHeight = sv.documentView?.bounds.height ?? 0
                let viewHeight = sv.contentView.bounds.height
                let maxOffset = max(0, docHeight - viewHeight)
                if currentOffset < maxOffset {
                    let newOffset = min(currentOffset + 0.5, maxOffset)
                    sv.contentView.scroll(to: NSPoint(x: 0, y: newOffset))
                } else {
                    // reached bottom, stop auto-scroll
                }
            }
        }
    }
}

// MARK: - GIF 动画图片视图

struct AnimatedImageView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.image = NSImage(data: data)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(data: data)
    }
}

/// 判断 item 是否有富文本样式
extension ClipboardItem {
    var hasRichText: Bool {
        type == .text && (htmlData != nil || rtfData != nil)
    }
}
