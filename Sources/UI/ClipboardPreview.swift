import SwiftUI

struct ClipboardRow: View {
    let item: ClipboardItem
    let title: String
    let favorite: Bool

    var body: some View {
        HStack(spacing: PanelStyle.gap) {
            ClipboardThumbnail(item: item, compact: true)
                .frame(width: PanelStyle.thumbnailSize, height: PanelStyle.thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: PanelStyle.thumbnailCorner))

            VStack(alignment: .leading, spacing: PanelStyle.segmentInset) {
                Text(title)
                    .font(PanelStyle.rowFont)
                    .lineLimit(1)
                ClipboardMetadata(item: item, favorite: favorite)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, PanelStyle.itemInset)
        .padding(.vertical, PanelStyle.smallGap)
        .frame(minHeight: PanelStyle.rowHeight)
        .contentShape(Rectangle())
    }
}

struct ClipboardCard: View {
    let item: ClipboardItem
    let favorite: Bool

    var body: some View {
        VStack(spacing: 0) {
            if item.type == .text {
                if item.hasRichText && item.name == nil {
                    RichPreview(item: item)
                        .padding(PanelStyle.smallGap)
                } else {
                    Text(item.displayTitle)
                        .font(PanelStyle.bodyFont)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(PanelStyle.itemInset)
                }
            } else {
                ClipboardThumbnail(item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: PanelStyle.segmentInset) {
                if item.type == .file || (item.type == .image && item.name != nil) {
                    Text(item.displayTitle)
                        .font(PanelStyle.controlFont)
                        .lineLimit(1)
                }
                ClipboardMetadata(item: item, favorite: favorite)
            }
            .padding(.horizontal, PanelStyle.itemInset)
            .padding(.vertical, PanelStyle.smallGap)
        }
        .frame(height: PanelStyle.gridHeight)
        .contentShape(Rectangle())
    }
}

private struct ClipboardMetadata: View {
    let item: ClipboardItem
    let favorite: Bool

    var body: some View {
        HStack(spacing: PanelStyle.smallGap) {
            if let source = item.source {
                sourceIcon(source)
            }
            Text(item.timestamp, formatter: Self.dateFormatter).monospacedDigit()
            Spacer(minLength: 0)
            if favorite {
                LucideGlyph(.star, size: PanelStyle.sourceIconSize)
                    .foregroundStyle(PanelStyle.favorite)
                    .accessibilityHidden(true)
            }
        }
        .font(PanelStyle.metadataFont)
        .foregroundStyle(PanelStyle.muted)
    }

    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        return cache
    }()

    private func sourceIcon(_ source: ClipSource) -> some View {
        let key = source.bundleID as NSString
        let icon = Self.iconCache.object(forKey: key) ??
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID).map {
                let icon = NSWorkspace.shared.icon(forFile: $0.path)
                Self.iconCache.setObject(icon, forKey: key)
                return icon
            }
        return Group {
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                LucideGlyph(.appWindow, size: PanelStyle.sourceIconSize)
            }
        }
        .frame(width: PanelStyle.sourceIconSize, height: PanelStyle.sourceIconSize)
        .accessibilityLabel("来源应用：\(source.name)")
        .help(source.name)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ClipboardThumbnail: View {
    let item: ClipboardItem
    var compact = false

    var body: some View {
        Group {
            if item.type == .image, let data = item.imageData, let image = NSImage(data: data) {
                if item.imageFormat == .gif {
                    AnimatedPreview(image: image)
                } else {
                    Image(nsImage: image).resizable()
                        .aspectRatio(contentMode: compact ? .fill : .fit)
                }
            } else {
                LucideGlyph(symbol, size: compact ? PanelStyle.iconSize : PanelStyle.cardIconSize)
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(compact && item.type != .image ? .clear : surface)
        .accessibilityHidden(true)
    }

    private var symbol: LucideIcon {
        switch item.type {
        case .text: return .fileText
        case .image: return .image
        case .file: return .folder
        }
    }

    private var ink: Color {
        switch item.type {
        case .text: return compact ? PanelStyle.muted : PanelStyle.selection
        case .image: return PanelStyle.imageInk
        case .file: return PanelStyle.fileInk
        }
    }

    private var surface: Color {
        switch item.type {
        case .text: return PanelStyle.selectedControl
        case .image: return PanelStyle.imageSurface
        case .file: return PanelStyle.fileSurface
        }
    }
}

private extension ClipboardItem {
    var hasRichText: Bool { type == .text && (htmlData != nil || rtfData != nil) }
}

private struct AnimatedPreview: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.animates = !reduceMotion
        if view.image !== image { view.image = image }
    }
}

private struct RichPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ClipboardItem

    var body: some View {
        RichTextView(item: item)
            .background(Color(nsColor: PanelStyle.richPaper(for: colorScheme)))
            .clipShape(RoundedRectangle(cornerRadius: PanelStyle.itemCorner))
    }
}

private final class PreviewScrollView: NSScrollView {
    var previewEntered: (() -> Void)?
    var previewExited: (() -> Void)?
    var handlesWheel = false
    private var tracking: NSTrackingArea?

    override func scrollWheel(with event: NSEvent) {
        let offset = contentView.bounds.minY
        let limit = max(0, (documentView?.bounds.height ?? 0) - contentView.bounds.height)
        let canScroll = event.scrollingDeltaY > 0 ? offset > 0 : offset < limit
        if handlesWheel && canScroll {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override func mouseEntered(with event: NSEvent) { previewEntered?() }
    override func mouseExited(with event: NSEvent) { previewExited?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
}

private struct RichTextView: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ClipboardItem

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PreviewScrollView {
        let scroll = PreviewScrollView()
        scroll.drawsBackground = false

        let editor = NSTextView()
        editor.isEditable = false
        editor.isSelectable = false
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: PanelStyle.richInset, height: PanelStyle.richInset)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = editor

        let coordinator = context.coordinator
        scroll.previewEntered = { [weak scroll, weak coordinator] in
            if let scroll { coordinator?.schedule(scroll) }
        }
        scroll.previewExited = { [weak scroll, weak coordinator] in
            coordinator?.stop()
            scroll?.handlesWheel = false
            scroll?.contentView.scroll(to: .zero)
        }
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ view: PreviewScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.reduceMotion = reduceMotion
        guard coordinator.itemID != item.id || coordinator.colorScheme != colorScheme,
              let editor = view.documentView as? NSTextView else { return }
        coordinator.itemID = item.id
        coordinator.colorScheme = colorScheme
        let rich = item.richText ?? NSAttributedString(string: item.plainText ?? "")
        let string = rich.string as NSString
        let firstContent = string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted).location
        let start = firstContent == NSNotFound ? rich.length : firstContent
        let length = min(rich.length - start, PanelStyle.richMaxLength)
        let range = NSRange(location: start, length: length)
        let excerpt = NSMutableAttributedString(attributedString: rich.attributedSubstring(from: range))
        let paper = PanelStyle.richPaper(for: colorScheme)
        let excerptRange = NSRange(location: 0, length: excerpt.length)
        excerpt.enumerateAttributes(in: excerptRange) { attributes, run, _ in
            if let font = attributes[.font] as? NSFont, font.pointSize > PanelStyle.richPreviewFontSize {
                let resized = NSFontManager.shared.convert(font, toSize: PanelStyle.richPreviewFontSize)
                excerpt.addAttribute(.font, value: resized, range: run)
            }
            let background = attributes[.backgroundColor] as? NSColor ?? paper
            let foreground = attributes[.foregroundColor] as? NSColor ?? .black
            if let ground = background.relativeLuminance, let ink = foreground.relativeLuminance,
               (max(ground, ink) + 0.05) / (min(ground, ink) + 0.05) < 4.5 {
                excerpt.addAttribute(.foregroundColor, value: ground < 0.18 ? NSColor.white : NSColor.black, range: run)
            } else if attributes[.foregroundColor] == nil {
                excerpt.addAttribute(.foregroundColor, value: foreground, range: run)
            }
        }
        editor.textStorage?.setAttributedString(excerpt)
    }

    static func dismantleNSView(_ nsView: PreviewScrollView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var itemID: UUID?
        var colorScheme: ColorScheme?
        var reduceMotion = false {
            didSet {
                if reduceMotion { scrollTimer?.invalidate() }
            }
        }
        private var hoverTimer: Timer?
        private var scrollTimer: Timer?

        func schedule(_ view: PreviewScrollView) {
            stop()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self, weak view] _ in
                guard let self, let view else { return }
                view.handlesWheel = true
                if !self.reduceMotion { self.startAutoScroll(view) }
            }
        }

        func stop() {
            hoverTimer?.invalidate()
            scrollTimer?.invalidate()
        }

        private func startAutoScroll(_ view: PreviewScrollView) {
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak view] timer in
                guard let view else { timer.invalidate(); return }
                let frame = view.contentView.bounds
                let limit = max(0, (view.documentView?.bounds.height ?? 0) - frame.height)
                guard frame.minY < limit else { timer.invalidate(); return }
                view.contentView.scroll(to: NSPoint(x: 0, y: min(frame.minY + 0.5, limit)))
            }
        }
    }
}

private extension NSColor {
    var relativeLuminance: CGFloat? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
}
