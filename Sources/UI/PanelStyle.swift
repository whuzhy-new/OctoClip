import SwiftUI

enum PanelStyle {
    static let preferredSize = CGSize(width: 688, height: 496)
    static let settingsSize = CGSize(width: 520, height: 376)
    static let screenMargin: CGFloat = 16
    static let windowShadowInset: CGFloat = 12
    static let corner: CGFloat = 22
    static let searchCorner: CGFloat = 12
    static let trayCorner: CGFloat = 18
    static let itemCorner: CGFloat = 12
    static let panelInset: CGFloat = 14
    static let horizontalInset: CGFloat = 20
    static let itemInset: CGFloat = 12
    static let smallGap: CGFloat = 6
    static let gap: CGFloat = 10
    static let sectionGap: CGFloat = 14
    static let toolbarSeparatorHeight: CGFloat = 16
    static let segmentInset: CGFloat = 3
    static let searchHeight: CGFloat = 36
    static let searchScopeWidth: CGFloat = 144
    static let toolHeight: CGFloat = 36
    static let toolWidth: CGFloat = 40
    static let toolTitleMaxWidth: CGFloat = 54
    static let segmentHeight: CGFloat = 30
    static let settingsRowHeight: CGFloat = 50
    static let settingsIconSize: CGFloat = 24
    static let settingsValueWidth: CGFloat = 150
    static let editorWidth: CGFloat = 420
    static let editorTextHeight: CGFloat = 120
    static let editorFormHeight: CGFloat = 328
    static let sourceIconSize: CGFloat = 13
    static let rowHeight: CGFloat = 46
    static let thumbnailSize: CGFloat = 30
    static let thumbnailCorner: CGFloat = 8
    static let gridMinimumWidth: CGFloat = 150
    static let gridHeight: CGFloat = 144
    static let selectionWidth: CGFloat = 2
    static let outlineWidth: CGFloat = 1
    static let windowShadowRadius: CGFloat = 7
    static let windowShadowOffset: CGFloat = 3
    static let trayShadowRadius: CGFloat = 6
    static let trayShadowOffset: CGFloat = 2
    static let cardShadowRadius: CGFloat = 3
    static let cardShadowOffset: CGFloat = 1
    static let richInset: CGFloat = 4
    static let richMaxLength = 500
    static let richPreviewFontSize: CGFloat = 15
    static let chromeOpacity = 0.90
    static let searchFillOpacity = 0.72

    static let searchFont = Font.system(size: 16)
    static let titleFont = Font.system(size: 19, weight: .semibold)
    static let bodyFont = Font.system(size: 14, weight: .medium)
    static let rowFont = Font.system(size: 14)
    static let toolbarFont = Font.system(size: 13, weight: .medium)
    static let controlFont = Font.system(size: 13, weight: .semibold)
    static let metadataFont = Font.system(size: 11)
    static let badgeFont = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let iconSize: CGFloat = 15
    static let controlIconSize: CGFloat = 13
    static let statusIconSize: CGFloat = 16
    static let emptyIconSize: CGFloat = 26
    static let cardIconSize: CGFloat = 28

    static let chrome = adaptive(0xFAFBFD, 0x22252C)
    static let tray = adaptive(0xF8FAFD, 0x1F222B)
    static let card = adaptive(0xFFFFFF, 0x2B2F3B)
    static let control = adaptive(0xFAFBFF, 0x393E4E)
    static let searchSurface = adaptive(0xE1E9F5, 0x161922)
    static let editorField = adaptive(0xF1F4FA, 0x2B2F3B)
    static let selectedControl = adaptive(0xE7ECF9, 0x424C68)
    static let selection = adaptive(0x4054AE, 0xA4B3FF)
    static let selectedItem = adaptive(0xEAEFF8, 0x303A54)
    static let hover = adaptive(0xEEF2F9, 0x2C313D)
    static let border = adaptive(0x9AA5BD, 0x78829B)
    static let windowShadow = adaptive(0x172032, 0x000000).opacity(0.16)
    static let trayShadow = adaptive(0x29354F, 0x000000).opacity(0.04)
    static let cardShadow = adaptive(0x29354F, 0x000000).opacity(0.025)
    static let text = adaptive(0x202437, 0xF1F3FB)
    static let separator = text.opacity(0.12)
    static let muted = adaptive(0x575F75, 0xB4BCD1)
    static let favorite = adaptive(0x835513, 0xFFD089)
    static let fileInk = adaptive(0x78531B, 0xEED3A4)
    static let fileSurface = adaptive(0xF5EAD7, 0x443728)
    static let imageInk = adaptive(0x26655E, 0x98DBCB)
    static let imageSurface = adaptive(0xDEEFEB, 0x293F3B)
    private static let lightRichPaper = NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    private static let darkRichPaper = NSColor(srgbRed: 0.16, green: 0.18, blue: 0.23, alpha: 1)

    static func richPaper(for scheme: ColorScheme) -> NSColor {
        scheme == .dark ? darkRichPaper : lightRichPaper
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

struct PanelShell<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PanelStyle.corner, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(PanelStyle.panelInset)
            .background {
                ZStack {
                    if !reduceTransparency { PanelBackdrop() }
                    PanelStyle.chrome.opacity(reduceTransparency ? 1 : PanelStyle.chromeOpacity)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(PanelStyle.border, lineWidth: PanelStyle.outlineWidth)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: PanelStyle.windowShadow, radius: PanelStyle.windowShadowRadius,
                    y: PanelStyle.windowShadowOffset)
            .padding(PanelStyle.windowShadowInset)
            .foregroundStyle(PanelStyle.text)
            .tint(PanelStyle.selection)
    }
}

private struct PanelBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PanelGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: Content

    var body: some View {
        #if OCTOCLIP_LIQUID_GLASS
        if #available(macOS 26, *), !reduceTransparency {
            GlassEffectContainer(spacing: PanelStyle.smallGap) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// Raised surfaces for grouped settings.
private struct PanelTray: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelStyle.trayCorner)
        content
            .clipShape(shape)
            .background {
                shape.fill(PanelStyle.tray)
                    .shadow(color: PanelStyle.trayShadow, radius: PanelStyle.trayShadowRadius,
                            y: PanelStyle.trayShadowOffset)
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(PanelStyle.border, lineWidth: PanelStyle.outlineWidth)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct PanelGlass<GlassShape: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: GlassShape
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if OCTOCLIP_LIQUID_GLASS
        if #available(macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background {
                shape.fill(PanelStyle.control)
                    .shadow(color: PanelStyle.cardShadow, radius: PanelStyle.cardShadowRadius,
                            y: PanelStyle.cardShadowOffset)
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(PanelStyle.border, lineWidth: PanelStyle.outlineWidth)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func panelTray() -> some View {
        modifier(PanelTray())
    }

    func panelGlass<GlassShape: InsettableShape>(in shape: GlassShape, interactive: Bool = false) -> some View {
        modifier(PanelGlass(shape: shape, interactive: interactive))
    }

    @ViewBuilder
    func panelGlass(interactive: Bool = false, standalone: Bool = true) -> some View {
        if standalone {
            panelGlass(in: Capsule(), interactive: interactive)
        } else {
            self
        }
    }
}

struct PanelIconButton: View {
    let symbol: LucideIcon
    let label: String
    var active = false
    var visibleTitle: String? = nil
    var grouped = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if let visibleTitle {
                    Text(visibleTitle)
                        .font(PanelStyle.toolbarFont)
                        .lineLimit(1)
                        .frame(maxWidth: PanelStyle.toolTitleMaxWidth)
                        .padding(.horizontal, PanelStyle.gap)
                } else {
                    LucideGlyph(symbol)
                }
            }
            .foregroundStyle(active ? PanelStyle.selection : PanelStyle.text)
            .frame(minWidth: PanelStyle.toolWidth)
            .frame(height: grouped ? PanelStyle.segmentHeight : PanelStyle.toolHeight)
            .background {
                if grouped && active {
                    Capsule().fill(PanelStyle.selectedControl)
                } else if grouped && hovered && isEnabled {
                    Capsule().fill(PanelStyle.hover)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .panelGlass(interactive: true, standalone: !grouped)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(label)
    }
}

struct PanelPrimaryButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: String
    let action: () -> Void

    @ViewBuilder var body: some View {
        #if OCTOCLIP_LIQUID_GLASS
        if #available(macOS 26, *), !reduceTransparency {
            Button(title, action: action).buttonStyle(.glassProminent)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        Button(title, action: action).buttonStyle(.borderedProminent)
    }
}

struct PanelSegment<Choice: Hashable> {
    let choice: Choice
    let title: String
    var symbol: LucideIcon? = nil
}

struct PanelSegments<Choice: Hashable>: View {
    let label: String
    let options: [PanelSegment<Choice>]
    @Binding var selection: Choice
    var iconsOnly = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.choice) { option in
                let selected = selection == option.choice
                Button {
                    selection = option.choice
                } label: {
                    HStack(spacing: PanelStyle.smallGap) {
                        if let symbol = option.symbol { LucideGlyph(symbol, size: PanelStyle.controlIconSize) }
                        if !iconsOnly { Text(option.title) }
                    }
                    .font(PanelStyle.toolbarFont)
                    .foregroundStyle(selected ? PanelStyle.selection : PanelStyle.muted)
                    .padding(.horizontal, iconsOnly ? PanelStyle.gap : PanelStyle.itemInset)
                    .frame(height: PanelStyle.segmentHeight)
                    .background(selected ? PanelStyle.selectedControl : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(option.title)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
