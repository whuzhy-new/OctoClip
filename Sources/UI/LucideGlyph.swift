import AppKit
import SwiftUI

enum LucideIcon: String, CaseIterable {
    case appWindow = "app-window"
    case calendarDays = "calendar-days"
    case chevronLeft = "chevron-left"
    case circle
    case circleCheck = "circle-check"
    case circleEllipsis = "circle-ellipsis"
    case circleExclamation = "circle-exclamation-point"
    case circlePause = "circle-pause"
    case circleX = "circle-x"
    case clipboard
    case clock
    case ellipsis
    case eye
    case file
    case fileText = "file-text"
    case folder
    case grid = "grid-2x2"
    case hand
    case image
    case info
    case keyboard
    case list
    case listFilter = "list-filter"
    case listOrdered = "list-ordered"
    case refresh = "refresh-cw"
    case search
    case settings
    case star
    case starOff = "star-off"
    case type
    case undo = "undo-2"

    private static let cache = NSCache<NSString, NSImage>()

    func templateImage(size: CGFloat) -> NSImage? {
        let key = "\(rawValue)-\(size)" as NSString
        if let image = Self.cache.object(forKey: key) { return image }
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "svg", subdirectory: "Lucide"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        Self.cache.setObject(image, forKey: key)
        return image
    }

    func menuBarImage(label: String) -> NSImage? {
        guard let image = templateImage(size: PanelStyle.statusIconSize)?.copy() as? NSImage else { return nil }
        image.accessibilityDescription = label
        return image
    }
}

// The same bundled templates supply SwiftUI controls and the AppKit status item.
struct LucideGlyph: View {
    let icon: LucideIcon
    let size: CGFloat

    init(_ icon: LucideIcon, size: CGFloat = PanelStyle.iconSize) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Group {
            if let image = icon.templateImage(size: size) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}
