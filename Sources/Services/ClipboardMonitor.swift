import AppKit
import Combine

class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var changeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // 图片格式 UTI 常量
    private static let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
    private static let jpegType = NSPasteboard.PasteboardType("public.jpeg")
    private static let heicType = NSPasteboard.PasteboardType("public.heic")
    private static let webpType = NSPasteboard.PasteboardType("org.webmproject.webp")

    private init() {}

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount

        guard let types = pb.types else { return }

        if types.contains(.fileURL) {
            handleFile(pb)
        } else if types.contains(Self.gifType) {
            handleGIF(pb)
        } else if types.contains(.tiff) || types.contains(.png) ||
                  types.contains(Self.jpegType) || types.contains(Self.heicType) ||
                  types.contains(Self.webpType) {
            handleImage(pb, types: types)
        } else if types.contains(.string) || types.contains(.rtf) || types.contains(.html) {
            handleText(pb)
        }
    }

    private func handleText(_ pb: NSPasteboard) {
        let plainText = pb.string(forType: .string)
        let rtfData = pb.data(forType: .rtf)
        let htmlData = pb.data(forType: .html)

        guard plainText != nil || rtfData != nil || htmlData != nil else { return }

        let item = ClipboardItem(
            id: UUID(),
            type: .text,
            timestamp: Date(),
            plainText: plainText,
            rtfData: rtfData,
            htmlData: htmlData,
            imageData: nil,
            imageFormat: nil,
            fileURLs: nil
        )
        DispatchQueue.main.async {
            ClipboardStore.shared.add(item)
        }
    }

    private func handleGIF(_ pb: NSPasteboard) {
        guard let gifData = pb.data(forType: Self.gifType) else { return }

        let item = ClipboardItem(
            id: UUID(),
            type: .image,
            timestamp: Date(),
            plainText: nil,
            rtfData: nil,
            htmlData: nil,
            imageData: gifData,
            imageFormat: .gif,
            fileURLs: nil
        )
        DispatchQueue.main.async {
            ClipboardStore.shared.add(item)
        }
    }

    private func handleImage(_ pb: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        let extracted: (data: Data, format: ImageFormat)? = {
            if types.contains(.png), let data = pb.data(forType: .png) {
                return (data, .png)
            }
            if types.contains(Self.jpegType), let data = pb.data(forType: Self.jpegType) {
                return (data, .jpeg)
            }
            if types.contains(Self.heicType), let data = pb.data(forType: Self.heicType) {
                return (data, .heic)
            }
            if types.contains(Self.webpType), let data = pb.data(forType: Self.webpType) {
                return (data, .webp)
            }
            // fallback: 通过 NSImage 转 PNG
            guard let image = NSImage(pasteboard: pb),
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
            return (pngData, .png)
        }()

        guard let (data, format) = extracted else { return }

        let item = ClipboardItem(
            id: UUID(),
            type: .image,
            timestamp: Date(),
            plainText: nil,
            rtfData: nil,
            htmlData: nil,
            imageData: data,
            imageFormat: format,
            fileURLs: nil
        )
        DispatchQueue.main.async {
            ClipboardStore.shared.add(item)
        }
    }

    private func handleFile(_ pb: NSPasteboard) {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return }

        let item = ClipboardItem(
            id: UUID(),
            type: .file,
            timestamp: Date(),
            plainText: nil,
            rtfData: nil,
            htmlData: nil,
            imageData: nil,
            imageFormat: nil,
            fileURLs: urls
        )
        DispatchQueue.main.async {
            ClipboardStore.shared.add(item)
        }
    }
}
