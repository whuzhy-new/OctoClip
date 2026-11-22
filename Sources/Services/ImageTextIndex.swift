import AppKit
import ImageIO
import Vision

final class ImageTextIndex: ObservableObject {
    @Published private(set) var results: [UUID: String] = [:]
    @Published private(set) var indexing = false

    private let worker = DispatchQueue(label: "com.octoclip.ocr", qos: .utility)
    private var activeID: UUID?
    private var items: [ClipboardItem] = []
    private var retainedIDs: Set<UUID> = []

    func update(_ items: [ClipboardItem]) {
        var ids: Set<UUID> = []
        self.items = items.filter { $0.supportsTextRecognition && ids.insert($0.id).inserted }
        retainedIDs = ids
        let retained = results.filter { ids.contains($0.key) }
        if retained.count != results.count { results = retained }
        indexNext()
    }

    func prioritize(_ item: ClipboardItem) {
        guard let index = items.firstIndex(of: item) else { return }
        let first = items.remove(at: index)
        items.insert(first, at: 0)
        indexNext()
    }

    private func indexNext() {
        guard activeID == nil else { return }
        guard let item = items.first(where: { results[$0.id] == nil }), let data = item.imageData else {
            if indexing { indexing = false }
            return
        }
        activeID = item.id
        if !indexing { indexing = true }
        worker.async { [weak self] in
            let text = autoreleasepool { Self.recognize(data) }
            DispatchQueue.main.async {
                guard let self else { return }
                if self.retainedIDs.contains(item.id) { self.results[item.id] = text }
                self.activeID = nil
                self.indexNext()
            }
        }
    }

    static func recognize(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1 else { return "" }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let supported = try? request.supportedRecognitionLanguages() {
            let preferred = ["zh-Hans", "zh-Hant", "en-US"].filter { supported.contains($0) }
            if !preferred.isEmpty { request.recognitionLanguages = preferred }
        }
        if #available(macOS 13, *) { request.automaticallyDetectsLanguage = true }
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            return ""
        }
    }
}
