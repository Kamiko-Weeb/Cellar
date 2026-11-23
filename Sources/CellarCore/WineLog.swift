import Foundation

/// The Wine log a bottle's launcher writes to Contents/SharedSupport/Logs/LastRunWine.log
/// when "Debug Mode" is on.
///
/// Two launcher habits shape this. Every launcher run truncates the file, so before Cellar starts
/// another run it copies the log aside (`preserve`). And the file isn't opened for appending, so a
/// program that is still running keeps writing at its old offset after a truncation, leaving a run
/// of NUL bytes (a sparse hole) in front of its new output. Reads drop those bytes.
public enum WineLog {
    /// Past this much data the live log is copied aside and emptied.
    static let liveLimit = 4 << 20
    /// How much of the end of a log a copy or a read keeps.
    static let keptTail = 2 << 20
    /// Copies kept per bottle, newest first.
    static let keptCopies = 3

    public static func folder(for bottle: Bottle) -> URL {
        bottle.contents.appending(path: "SharedSupport/Logs")
    }

    public static func live(for bottle: Bottle) -> URL {
        folder(for: bottle).appending(path: "LastRunWine.log")
    }

    /// Cellar's copies of earlier logs, oldest first.
    static func copies(for bottle: Bottle) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder(for: bottle).path)) ?? []
        return names.filter { $0.hasPrefix("Cellar-") && $0.hasSuffix(".log") }.sorted()
            .map { folder(for: bottle).appending(path: $0) }
    }

    /// The most recently written log that has something in it.
    public static func newest(for bottle: Bottle) -> URL? {
        ([live(for: bottle)] + copies(for: bottle))
            .filter { stored($0) > 0 }
            .max { modified($0) < modified($1) }
    }

    /// Up to the last couple of MB of a log, without the NUL holes truncation leaves.
    public static func read(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(keptTail) ? size - UInt64(keptTail) : 0)
        var data = (try? handle.readToEnd()) ?? Data()
        data.removeAll { $0 == 0 }
        return String(decoding: data, as: UTF8.self)
    }

    /// Copies the live log aside before a new launcher run wipes it.
    public static func preserve(_ bottle: Bottle, now: Date = Date()) {
        let source = live(for: bottle)
        guard stored(source) > 0 else { return }
        let text = read(source)
        guard !text.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let copy = folder(for: bottle).appending(path: "Cellar-\(formatter.string(from: now)).log")
        try? Data(text.utf8).write(to: copy, options: .atomic)
        for old in copies(for: bottle).dropLast(keptCopies) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// Keeps a long session from filling the disk: once the live log holds more than a few MB, its
    /// end is copied aside and the file emptied. Emptying is safe while Wine writes to it, since
    /// the data after the hole is all that takes up space.
    public static func enforceLimit(_ bottle: Bottle) {
        let url = live(for: bottle)
        guard stored(url) > liveLimit else { return }
        preserve(bottle)
        truncate(url)
    }

    /// Empties the live log and deletes Cellar's copies.
    public static func clear(_ bottle: Bottle) {
        truncate(live(for: bottle))
        for copy in copies(for: bottle) {
            try? FileManager.default.removeItem(at: copy)
        }
    }

    private static func truncate(_ url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        try? handle.truncate(atOffset: 0)
        try? handle.close()
    }

    /// Bytes actually on disk, which for a log with a hole is far less than its length.
    static func stored(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// A Wine log split into lines, with the ones that explain crashes marked and summed up.
public struct WineLogReport: Sendable {
    public enum Kind: Sendable {
        case plain
        /// Startup chatter that is always there (msync, Rosetta's mmap complaints).
        case noise
        case module
        case graphics
        case unimplemented
        case pageFault

        public var matters: Bool { self != .plain && self != .noise }
    }

    public struct Line: Identifiable, Sendable {
        public let id: Int
        public let text: String
        public let kind: Kind
    }

    public let lines: [Line]
    /// One entry per distinct problem, such as "Missing DLL: xinput1_4.dll".
    public let summary: [String]

    public init(text: String) {
        var lines: [Line] = []
        var summary: [String] = []
        var graphicsErrors = 0
        func note(_ item: String) {
            if !summary.contains(item) { summary.append(item) }
        }
        for (index, raw) in text.split(whereSeparator: \.isNewline).enumerated() {
            let text = String(raw)
            let kind = Self.kind(of: text)
            switch kind {
            case .pageFault:
                note("Crash: " + Self.slice(of: text, from: "page fault", keepingMarker: true, upTo: " (thread"))
            case .unimplemented:
                note("Unimplemented function: " + Self.slice(of: text, from: "unimplemented function ", keepingMarker: false, upTo: ","))
            case .module:
                if let dll = Self.missingDLL(in: text) { note("Missing DLL: \(dll)") }
            case .graphics:
                graphicsErrors += 1
            case .plain, .noise:
                break
            }
            lines.append(Line(id: index, text: text, kind: kind))
        }
        if graphicsErrors > 0 {
            summary.append("Graphics errors: \(graphicsErrors) (d3d, vkd3d or DXMT)")
        }
        self.lines = lines
        self.summary = summary
    }

    static func kind(of line: String) -> Kind {
        let lower = line.lowercased()
        if lower.contains("page fault") { return .pageFault }
        if lower.contains("unimplemented function") { return .unimplemented }
        if lower.contains("err:module") { return .module }
        if lower.contains("err:d3d") || lower.contains("err:vkd3d")
            || (lower.contains("dxmt") && (lower.contains("err") || lower.contains("fail"))) {
            return .graphics
        }
        if lower.hasPrefix("msync:") || lower.contains("err:virtual:try_map_free_area") { return .noise }
        return .plain
    }

    /// The DLL in Wine's "Library foo.dll (which is needed by …) not found".
    static func missingDLL(in line: String) -> String? {
        guard let start = line.range(of: "Library ", options: .caseInsensitive),
              line.range(of: "not found", options: .caseInsensitive) != nil
        else { return nil }
        return line[start.upperBound...].split(separator: " ").first.map(String.init)
    }

    private static func slice(of line: String, from marker: String, keepingMarker: Bool, upTo end: String) -> String {
        guard let start = line.range(of: marker, options: .caseInsensitive) else { return line }
        let rest = line[(keepingMarker ? start.lowerBound : start.upperBound)...]
        let cut = rest.range(of: end).map { rest[..<$0.lowerBound] } ?? rest
        return cut.trimmingCharacters(in: .whitespaces)
    }
}
