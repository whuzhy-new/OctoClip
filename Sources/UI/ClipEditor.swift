import SwiftUI

enum ClipEditorRequest: Identifiable {
    case metadata(ClipboardItem, favorite: Bool)
    case create(group: String?)
    case fill(ClipboardItem, queued: PasteQueue.Entry? = nil)
    case merge([ClipboardItem])

    var id: String {
        switch self {
        case .metadata(let item, _): return "edit-\(item.id)"
        case .create: return "create"
        case .fill(let item, _): return "fill-\(item.id)"
        case .merge: return "merge"
        }
    }
}

// The panel rows handle immediate actions. This sheet owns draft fields and commits them together.
struct ClipEditor: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let request: ClipEditorRequest
    let groups: [String]
    let onCommit: (ClipboardItem) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var group: String
    @State private var link: String
    @State private var content: String
    @State private var template: Bool
    @State private var values: [UUID: [String: String]] = [:]
    @FocusState private var firstField: Bool

    init(request: ClipEditorRequest, groups: [String], onCommit: @escaping (ClipboardItem) -> Void,
         onCancel: @escaping () -> Void) {
        self.request = request
        self.groups = groups
        self.onCommit = onCommit
        self.onCancel = onCancel
        switch request {
        case .metadata(let item, _), .fill(let item, _):
            _name = State(initialValue: item.name ?? "")
            _group = State(initialValue: item.group ?? "")
            _link = State(initialValue: item.sourceURL?.absoluteString ?? "")
            _content = State(initialValue: item.readableText ?? "")
            _template = State(initialValue: item.template == true)
        case .create, .merge:
            _name = State(initialValue: "")
            if case .create(let group) = request {
                _group = State(initialValue: group ?? "")
            } else {
                _group = State(initialValue: "")
            }
            _link = State(initialValue: "")
            _content = State(initialValue: "")
            _template = State(initialValue: false)
        }
    }

    private var title: String {
        switch request {
        case .metadata(_, let favorite): return favorite ? "编辑收藏" : "编辑条目"
        case .create: return "新建片段"
        case .fill: return name.isEmpty ? "填写模板" : name
        case .merge: return "合并前填写模板"
        }
    }

    private var templateFields: [String] {
        ClipDocument.fieldNames(in: content)
    }

    private var fillItems: [ClipboardItem]? {
        switch request {
        case .fill(let item, _): return [item]
        case .merge(let items): return items.filter { !$0.templateFields.isEmpty }
        default: return nil
        }
    }

    private var canEditText: Bool {
        switch request {
        case .create: return true
        case .metadata(let item, let favorite): return favorite && item.type == .text
        case .fill, .merge: return false
        }
    }

    private var canEditGroup: Bool {
        switch request {
        case .create: return true
        case .metadata(_, let favorite): return favorite
        case .fill, .merge: return false
        }
    }

    private var url: URL? { ClipDocument.webURL(link.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var invalidLink: Bool { !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && url == nil }

    private var valid: Bool {
        if let fillItems {
            return fillItems.allSatisfy { item in
                item.templateFields.allSatisfy { values[item.id]?[$0] != nil }
            }
        }
        if invalidLink || (canEditText && template && templateFields.isEmpty) { return false }
        if case .create = request { return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PanelStyle.sectionGap) {
            Text(title).font(PanelStyle.titleFont).lineLimit(1)
            ScrollView {
                VStack(alignment: .leading, spacing: PanelStyle.gap) {
                    if let fillItems {
                        fillFields(for: fillItems)
                    } else {
                        metadataFields
                    }
                }
                .padding(.vertical, PanelStyle.segmentInset)
                .padding(.horizontal, PanelStyle.segmentInset)
            }
            .frame(maxHeight: PanelStyle.editorFormHeight)
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                PanelPrimaryButton(title: fillItems == nil ? "保存" : "粘贴", action: commit)
                    .keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .padding(PanelStyle.horizontalInset)
        .frame(width: PanelStyle.editorWidth)
        .onAppear { firstField = true }
    }

    private func fillFields(for items: [ClipboardItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let fields = item.templateFields
            if items.count > 1 {
                Text(item.name ?? "模板 \(index + 1)").font(PanelStyle.controlFont)
            }
            ForEach(fields, id: \.self) { name in
                let binding = Binding(get: { values[item.id]?[name] ?? "" },
                                      set: { values[item.id, default: [:]][name] = $0 })
                if index == 0 && name == fields.first {
                    TextField(name, text: binding).focused($firstField)
                } else {
                    TextField(name, text: binding)
                }
            }
        }
    }

    private var metadataFields: some View {
        VStack(alignment: .leading, spacing: PanelStyle.gap) {
            TextField("名称", text: $name).focused($firstField)
            if canEditGroup {
                HStack(spacing: PanelStyle.smallGap) {
                    TextField("收藏分组", text: $group)
                    if !groups.isEmpty {
                        Menu("现有分组") {
                            ForEach(groups, id: \.self) { groupName in
                                Button(groupName) { group = groupName }
                            }
                            Divider()
                            Button("取消分组") { group = "" }
                        }
                        .fixedSize()
                    }
                }
            }
            TextField("来源网址", text: $link)
            if invalidLink {
                Text("请输入有效的 http 或 https 网址。").font(PanelStyle.metadataFont)
            }
            if canEditText {
                snippetEditor
                    .font(PanelStyle.bodyFont)
                    .frame(height: PanelStyle.editorTextHeight)
                    .padding(PanelStyle.segmentInset)
                    .background(PanelStyle.editorField, in: RoundedRectangle(cornerRadius: PanelStyle.itemCorner))
                    .overlay {
                        if contrast == .increased {
                            RoundedRectangle(cornerRadius: PanelStyle.itemCorner)
                                .strokeBorder(PanelStyle.border, lineWidth: PanelStyle.outlineWidth)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("片段内容")
                Toggle("作为模板", isOn: $template)
                if template && templateFields.isEmpty {
                    Text("用 {{名称}} 标记需要填写的字段。").font(PanelStyle.metadataFont)
                }
            }
        }
    }

    @ViewBuilder
    private var snippetEditor: some View {
        let editor = TextEditor(text: $content)
        if #available(macOS 13, *) {
            editor.scrollContentBackground(.hidden)
        } else {
            editor
        }
    }

    private func commit() {
        guard valid else { return }
        let item: ClipboardItem
        switch request {
        case .fill(let original, _):
            onCommit(.text(ClipDocument.fill(content, values: values[original.id] ?? [:]), id: original.id))
            return
        case .merge(let clips):
            onCommit(.text(ClipDocument.mergedText(clips, values: values)))
            return
        case .create:
            item = .text(content)
        case .metadata(let original, let favorite):
            if favorite, original.type == .text, content != (original.readableText ?? "") {
                var edited = ClipboardItem.text(content, id: original.id, timestamp: original.timestamp)
                edited.source = original.source
                item = edited
            } else {
                item = original
            }
        }
        var edited = item
        edited.name = normalized(name)
        edited.group = normalized(group)
        edited.sourceURL = url
        edited.template = canEditText && template ? true : nil
        onCommit(edited)
    }

    private func normalized(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
