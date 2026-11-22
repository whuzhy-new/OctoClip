import Foundation
import Combine

final class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    struct Entry {
        let revision: UUID
        let item: ClipboardItem
    }

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var manualPayload: ClipboardItem?
    private var revision = UUID()

    var nextEntry: Entry? {
        guard manualPayload == nil, let item = items.first else { return nil }
        return Entry(revision: revision, item: item)
    }

    func start(_ clips: [ClipboardItem]) {
        guard !PasteService.shared.isPasting else { return }
        PasteService.shared.clearFeedback()
        revision = UUID()
        manualPayload = nil
        items = clips
    }

    func clear() {
        start([])
    }

    func paste(_ entry: Entry, filled: ClipboardItem? = nil) {
        guard entry.revision == revision, manualPayload == nil,
              filled != nil || entry.item.templateFields.isEmpty else { return }
        let payload = filled ?? entry.item
        PasteService.shared.pasteToFrontApp(payload, mode: .original) { [weak self] outcome in
            self?.record(outcome, for: entry, payload: payload)
        }
    }

    func record(_ outcome: PasteService.Outcome, for entry: Entry, payload: ClipboardItem) {
        guard entry.revision == revision, manualPayload == nil else { return }
        switch outcome {
        case .sent:
            advance()
        case .copiedForManualPaste:
            manualPayload = payload
            PasteService.shared.clearFeedback()
        }
    }

    func recopy() {
        guard let manualPayload else { return }
        if !PasteService.shared.copyToClipboard(manualPayload, mode: .original) {
            PasteService.shared.report("复制失败，请重试。")
        } else {
            PasteService.shared.clearFeedback()
        }
    }

    func confirmManualPaste() {
        guard manualPayload != nil else { return }
        PasteService.shared.clearFeedback()
        advance()
    }

    private func advance() {
        revision = UUID()
        manualPayload = nil
        items.removeFirst()
    }
}
