import AppKit

private let usage = """
Usage:
  octoclip list [--scope history|favorites|all] [--type text|image|file]
                [--query TEXT] [--source APP] [--group NAME] [--since TIME] [--before TIME]
                [--limit 1-100] [--offset N] [--ocr] [--library DIRECTORY]
  octoclip get ID [--scope history|favorites|all] [--ocr] [--output IMAGE_PATH] [--library DIRECTORY]
  octoclip current [--ocr] [--output IMAGE_PATH]

Defaults: list searches history, get searches all, limit is 20, offset is 0.
Time: 30m, 24h, 7d, YYYY-MM-DD (local time), or an ISO 8601 timestamp.
Source: app name or bundle ID. Group: exact name, case insensitive.
Use next_offset from the JSON response for the next page.
--ocr includes recognized image text and extends keyword search to images.
--output exports the original image bytes to a new local file.
--library uses an alternate OctoClip library directory.
"""

private struct CLIError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

private enum Scope: String {
    case history, favorites, all
}

private enum Command: String {
    case list, get, current

    var options: Set<String> {
        switch self {
        case .list:
            return ["--scope", "--type", "--query", "--source", "--group", "--since",
                    "--before", "--limit", "--offset", "--ocr", "--library"]
        case .get:
            return ["--scope", "--ocr", "--output", "--library"]
        case .current:
            return ["--ocr", "--output"]
        }
    }
}

private struct Options {
    let command: Command
    let id: UUID?
    let values: [String: String]

    init(_ arguments: [String]) throws {
        var args = ArraySlice(arguments)
        guard let name = args.popFirst(), let command = Command(rawValue: name) else {
            throw CLIError("Expected list, get, or current. Use --help for usage.")
        }
        self.command = command
        if command == .get {
            guard let argument = args.popFirst(), let id = UUID(uuidString: argument) else {
                throw CLIError("get expects a clipboard item UUID.")
            }
            self.id = id
        } else {
            id = nil
        }

        var values: [String: String] = [:]
        while let flag = args.popFirst() {
            guard command.options.contains(flag) else { throw CLIError("Unknown option for \(name): \(flag)") }
            guard values[flag] == nil else { throw CLIError("Option specified twice: \(flag)") }
            if flag == "--ocr" {
                values[flag] = "true"
            } else {
                guard let value = args.popFirst(), !value.hasPrefix("--"), !value.isEmpty else {
                    throw CLIError("Missing value for \(flag).")
                }
                values[flag] = value
            }
        }
        self.values = values
    }

    var ocr: Bool { values["--ocr"] != nil }

    var scope: Scope {
        get throws {
            guard let value = values["--scope"] else { return command == .list ? .history : .all }
            guard let scope = Scope(rawValue: value) else { throw CLIError("Invalid --scope: \(value)") }
            return scope
        }
    }

    var libraryDirectory: URL {
        values["--library"].map(localURL) ?? ClipboardLibrary.defaultDirectory
    }

    func integer(_ flag: String, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value = values[flag] else { return fallback }
        guard let number = Int(value), range.contains(number) else {
            throw CLIError("\(flag) must be an integer in \(range.lowerBound)...\(range.upperBound).")
        }
        return number
    }
}

private struct Filters {
    let type: ClipboardItemType?
    let query: String?
    let source: String?
    let group: String?
    let since: Date?
    let before: Date?

    init(_ options: Options) throws {
        let values = options.values
        if let value = values["--type"] {
            guard let parsed = ClipboardItemType(rawValue: value) else {
                throw CLIError("Invalid --type: \(value)")
            }
            type = parsed
        } else {
            type = nil
        }
        query = values["--query"]
        source = values["--source"]
        group = values["--group"]
        let now = Date()
        since = try values["--since"].map { try Self.parseTime($0, now: now) }
        before = try values["--before"].map { try Self.parseTime($0, now: now) }
        if let since, let before, since >= before {
            throw CLIError("--since must be earlier than --before.")
        }
    }

    func matchesMetadata(_ item: ClipboardItem) -> Bool {
        if let type, item.type != type { return false }
        if let since, item.timestamp < since { return false }
        if let before, item.timestamp >= before { return false }
        if let group, item.group?.localizedCaseInsensitiveCompare(group) != .orderedSame { return false }
        if let source {
            return item.source?.name.localizedCaseInsensitiveContains(source) == true ||
                item.source?.bundleID.caseInsensitiveCompare(source) == .orderedSame
        }
        return true
    }

    private static func parseTime(_ value: String, now: Date) throws -> Date {
        let durations: [Character: Double] = ["m": 60, "h": 3_600, "d": 86_400]
        if let unit = value.last, let scale = durations[unit], let amount = Int(value.dropLast()), amount > 0 {
            return now.addingTimeInterval(-Double(amount) * scale)
        }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }

        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"
        if let date = day.date(from: value), day.string(from: date) == value { return date }
        throw CLIError("Invalid time: \(value). Use 30m, 24h, 7d, YYYY-MM-DD, or ISO 8601.")
    }
}

private struct ClipResult: Encodable {
    let id: UUID?
    let type: ClipboardItemType
    let timestamp: Date?
    let source: ClipSource?
    let sourceURL: String?
    let favorite: Bool?
    let name: String?
    let group: String?
    let preview: String
    let text: String?
    let html: String?
    let filePaths: [String]?
    let imageFormat: ImageFormat?
    let imageBytes: Int?
    let recognizedText: String?
    let outputPath: String?

    init(_ item: ClipboardItem, favorite: Bool?, full: Bool = false, recognizedText: String? = nil,
         outputPath: String? = nil) {
        id = favorite == nil ? nil : item.id
        type = item.type
        timestamp = favorite == nil ? nil : item.timestamp
        source = item.source
        sourceURL = item.sourceURL?.absoluteString
        self.favorite = favorite
        name = item.name
        group = item.group
        let plain = item.type == .text ? plainText(item) : nil
        let excerpt = plain ?? recognizedText ?? (item.type == .text ? "[Rich text]" : item.preview)
        preview = String(excerpt.prefix(200))
        text = full ? plain : nil
        html = full ? htmlText(item) : nil
        filePaths = full ? item.fileURLs?.filter(\.isFileURL).map(\.path) : nil
        imageFormat = item.imageFormat
        imageBytes = item.imageData?.count
        self.recognizedText = full ? recognizedText : nil
        self.outputPath = outputPath
    }
}

private struct Response: Encodable {
    var items: [ClipResult] = []
    var nextOffset: Int?
    var warnings: [String] = []
}

private func localURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
}

private func plainText(_ item: ClipboardItem) -> String? {
    if let text = item.plainText, !text.isEmpty { return text }
    if let rtf = item.rtfData, let text = NSAttributedString(rtf: rtf, documentAttributes: nil) {
        return text.string
    }
    return item.plainText
}

// Return HTML as data. Loading it as a document can fetch remote resources.
private func htmlText(_ item: ClipboardItem) -> String? {
    item.htmlData.flatMap { String(data: $0, encoding: .utf8) }
}

private func recognizesText(in item: ClipboardItem) -> String? {
    guard item.supportsTextRecognition, let image = item.imageData else { return nil }
    let text = ImageTextIndex.recognize(image)
    return text.isEmpty ? nil : text
}

private func exportImage(_ item: ClipboardItem, to path: String?) throws -> String? {
    guard let path else { return nil }
    guard item.type == .image, let image = item.imageData else {
        throw CLIError("--output requires a clipboard image.")
    }
    let url = localURL(path)
    do {
        try image.write(to: url, options: .withoutOverwriting)
    } catch {
        throw CLIError("Could not export image: \(error.localizedDescription)")
    }
    return url.path
}

private func list(_ items: [ClipboardItem], favorites: Set<UUID>, options: Options) throws -> Response {
    let filters = try Filters(options)
    let limit = try options.integer("--limit", default: 20, range: 1...100)
    let offset = try options.integer("--offset", default: 0, range: 0...Int.max)
    let sorted = items.sorted {
        if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
        return $0.id.uuidString < $1.id.uuidString
    }

    var response = Response()
    var skipped = 0
    for item in sorted where filters.matchesMetadata(item) {
        let recognized = options.ocr ? recognizesText(in: item) : nil
        if let query = filters.query, !matches(item, query: query, recognizedText: recognized) { continue }
        if skipped < offset {
            skipped += 1
            continue
        }
        if response.items.count == limit {
            response.nextOffset = skipped + limit
            break
        }
        response.items.append(ClipResult(item, favorite: favorites.contains(item.id), recognizedText: recognized))
    }
    return response
}

private func matches(_ item: ClipboardItem, query: String, recognizedText: String?) -> Bool {
    let content: String
    if item.type != .text {
        content = item.preview
    } else if let text = plainText(item), !text.isEmpty {
        content = text
    } else {
        content = htmlText(item) ?? ""
    }
    return [content, item.name, item.group, item.source?.name, item.source?.bundleID,
            item.sourceURL?.absoluteString, recognizedText].contains {
        $0?.localizedCaseInsensitiveContains(query) == true
    }
}

private func detail(_ item: ClipboardItem, favorite: Bool?, options: Options) throws -> ClipResult {
    let output = try exportImage(item, to: options.values["--output"])
    let ocr = options.ocr ? recognizesText(in: item) : nil
    return ClipResult(item, favorite: favorite, full: true, recognizedText: ocr, outputPath: output)
}

private func current(_ options: Options) throws -> Response {
    let bundleID = "com.octoclip.mac"
    let defaults = UserDefaults(suiteName: bundleID) ?? .standard
    if let pause = defaults.object(forKey: SettingsKey.capturePausedUntil) as? Date, pause > Date() {
        throw CLIError("Clipboard capture is paused in OctoClip.")
    }
    let pasteboard = NSPasteboard.general
    let revision = pasteboard.changeCount
    let item = ClipboardPasteboard.readItem(from: pasteboard, excludedApps: ClipboardPasteboard.excludedApps(in: defaults),
                                            ownBundleID: bundleID)
    guard pasteboard.changeCount == revision else { throw CLIError("Clipboard changed during the read. Try again.") }
    guard let item else {
        if options.values["--output"] != nil { throw CLIError("No readable image on the clipboard.") }
        return Response()
    }
    return Response(items: [try detail(item, favorite: nil, options: options)])
}

private func run(_ options: Options) throws -> Response {
    if options.command == .current { return try current(options) }
    let scope = try options.scope
    let snapshot: ClipboardLibrary.Snapshot
    do {
        snapshot = try ClipboardLibrary.read(from: options.libraryDirectory)
    } catch {
        throw CLIError("Could not read the OctoClip library: \(error.localizedDescription)")
    }
    let library = snapshot.library
    let favorites = Set(library.favorites.map(\.id))
    let items: [ClipboardItem]
    switch scope {
    case .history: items = library.history
    case .favorites: items = library.favorites
    case .all:
        var seen: Set<UUID> = []
        items = (library.favorites + library.history).filter { seen.insert($0.id).inserted }
    }

    var response: Response
    if let id = options.id {
        guard let item = items.first(where: { $0.id == id }) else { throw CLIError("Clipboard item not found: \(id)") }
        response = Response(items: [try detail(item, favorite: favorites.contains(id), options: options)])
    } else {
        response = try list(items, favorites: favorites, options: options)
    }
    if snapshot.hasDamagedHistory { response.warnings.append("Some history or favorite records could not be decoded.") }
    if snapshot.hasDamagedLegacyFavorites { response.warnings.append("Some legacy favorites could not be decoded.") }
    return response
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] ||
    (arguments.count == 2 && Command(rawValue: arguments[0]) != nil && arguments[1] == "--help") {
    print(usage)
} else {
    do {
        let response = try run(Options(arguments))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(response))
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        FileHandle.standardError.write(Data("octoclip: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
