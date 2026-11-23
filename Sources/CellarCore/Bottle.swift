import Foundation

/// A Sikarugir wrapper app: a self-contained Wine prefix plus the Wine engine that runs it.
public struct Bottle: Identifiable, Hashable, Sendable {
    public let url: URL
    /// The name Cellar shows. Bottles Cellar creates keep it in Info.plist because their
    /// folder names can't contain spaces; others just use the folder name.
    public let name: String

    /// Info.plist key holding the display name.
    static let nameKey = "CellarName"

    public init(url: URL) {
        // Directory listings return "Steam.app/" with a trailing slash; drop it so the same bottle always compares equal.
        self.url = URL(filePath: url.standardizedFileURL.path(percentEncoded: false), directoryHint: .notDirectory)
        let plist = NSDictionary(contentsOf: self.url.appending(path: "Contents/Info.plist"))
        name = plist?[Self.nameKey] as? String ?? self.url.deletingPathExtension().lastPathComponent
    }

    public static func == (lhs: Bottle, rhs: Bottle) -> Bool { lhs.url == rhs.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }

    public var id: URL { url }
    public var contents: URL { url.appending(path: "Contents") }
    public var driveC: URL { contents.appending(path: "drive_c") }
    public var launcher: URL { contents.appending(path: "MacOS/Sikarugir") }
    public var infoPlist: URL { contents.appending(path: "Info.plist") }

    /// The Wine prefix (its registry and drive letters). Sikarugir keeps it in SharedSupport/prefix,
    /// with `Contents/drive_c` only a link into it; wrappers without that folder use Contents itself.
    public var prefix: URL {
        let shared = contents.appending(path: "SharedSupport/prefix")
        return FileManager.default.fileExists(atPath: shared.path) ? shared : contents
    }

    /// "Wine 10.0", read from the engine's version file.
    public var engineName: String? {
        let file = contents.appending(path: "SharedSupport/wine/version")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let number = text.split(separator: " ").first { $0.first?.isNumber == true }
        return number.map { "Wine \($0)" }
    }

    /// Maps a Windows path such as `C:\Games\x.exe` to its macOS location through the wrapper's drive links.
    public func macURL(forWindowsPath path: String) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard normalized.count >= 2, normalized.dropFirst().first == ":" else { return nil }
        let link = prefix.appending(path: "dosdevices/\(normalized.prefix(1).lowercased()):")
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
        let root = target.hasPrefix("/")
            ? URL(fileURLWithPath: target)
            : link.deletingLastPathComponent().appending(path: target).standardizedFileURL
        let rest = normalized.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rest.isEmpty ? root : root.appending(path: rest)
    }

    public static var defaultFolder: URL {
        if let custom = ProcessInfo.processInfo.environment["CELLAR_BOTTLES_DIR"] {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/Sikarugir")
    }

    public static func discover(in folder: URL) -> [Bottle] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension == "app" && fm.fileExists(atPath: $0.appending(path: "Contents/SharedSupport/wine").path) }
            .map(Bottle.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
