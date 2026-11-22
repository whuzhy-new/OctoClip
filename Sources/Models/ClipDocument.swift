import AppKit

enum ClipDocument {
    private static let fields = try! NSRegularExpression(pattern: #"\{\{\s*([^\s{}]+)\s*\}\}"#)

    static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host?.isEmpty == false else { return nil }
        return url
    }

    static func fieldNames(in text: String) -> [String] {
        var seen: Set<String> = []
        return matches(in: text).compactMap { _, field in
            seen.insert(field).inserted ? field : nil
        }
    }

    static func fill(_ text: String, values: [String: String]) -> String {
        var result = ""
        var cursor = text.startIndex
        for (range, field) in matches(in: text) {
            result += String(text[cursor..<range.lowerBound]) + (values[field] ?? String(text[range]))
            cursor = range.upperBound
        }
        return result + text[cursor...]
    }

    static func mergedText(_ items: [ClipboardItem], values: [UUID: [String: String]] = [:]) -> String {
        items.compactMap { item -> String? in
            guard let text = item.readableText else { return nil }
            return values[item.id].map { fill(text, values: $0) } ?? text
        }.joined(separator: "\n\n")
    }

    private static func matches(in text: String) -> [(Range<String.Index>, String)] {
        fields.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let name = Range(match.range(at: 1), in: text) else { return nil }
            return (range, String(text[name]))
        }
    }

    static func richMarkdown(_ item: ClipboardItem) -> String? {
        guard let richText = item.richText else { return item.readableText }
        let body = richText.string as NSString
        var markdown = ""
        richText.enumerateAttributes(in: NSRange(location: 0, length: body.length)) { attributes, range, _ in
            let text = body.substring(with: range)
            let font = attributes[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            let strike = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            let marker = (traits.contains(.boldFontMask) ? "**" : "") + (traits.contains(.italicFontMask) ? "*" : "")
            let lines = text.components(separatedBy: CharacterSet.newlines)
            markdown += lines.map { line in
                let core = line.trimmingCharacters(in: .whitespaces)
                guard !core.isEmpty, let range = line.range(of: core) else { return line }
                var formatted = escape(core)
                if !marker.isEmpty { formatted = marker + formatted + marker }
                if strike { formatted = "~~" + formatted + "~~" }
                if let link, let url = webURL(link) { formatted = "[\(formatted)](\(destination(url)))" }
                return String(line[..<range.lowerBound]) + formatted + line[range.upperBound...]
            }.joined(separator: "\n")
        }
        return markdown
    }

    static func markdownList(_ items: [ClipboardItem], recognizedText: [UUID: String]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = .current
        let sections = items.enumerated().map { index, item in
            var lines = ["## \(index + 1). \(escape(String(item.displayTitle.prefix(96))))",
                         dateFormatter.string(from: item.timestamp)]
            if let source = item.source { lines[1] += " · " + escape(source.name) }
            if let url = item.sourceURL, webURL(url.absoluteString) != nil {
                lines.append("[来源链接](\(destination(url)))")
            }
            switch item.type {
            case .text:
                if let text = item.readableText { lines.append(quote(text)) }
            case .image:
                if let text = recognizedText[item.id], !text.isEmpty { lines.append(quote(text)) }
            case .file:
                for url in item.fileURLs ?? [] {
                    let label = escape(url.lastPathComponent)
                    lines.append(url.isFileURL ? "- [\(label)](\(destination(url)))" : "- \(label)")
                }
            }
            return lines.joined(separator: "\n\n")
        }
        return "# 剪贴资料\n\n" + sections.joined(separator: "\n\n") + "\n"
    }

    private static func quote(_ value: String) -> String {
        value.components(separatedBy: .newlines).map { "> " + escape($0) }.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        let punctuation = "\\\u{60}*_{}[]<>!|#~"
        return value.map { punctuation.contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    private static func destination(_ url: URL) -> String {
        "<" + url.absoluteString.replacingOccurrences(of: ">", with: "%3E") + ">"
    }
}
