import Foundation

public struct SteamGame: Identifiable, Hashable, Sendable {
    public let appID: Int
    public let name: String
    public let sizeOnDisk: Int64
    /// Poster art from Steam's local cache, when Steam has downloaded it.
    public let artwork: URL?

    public var id: Int { appID }
}

/// Reads the Windows Steam install inside a bottle to find installed games.
public enum SteamLibrary {
    /// Steamworks Common Redistributables: installed with almost every game, never something to play.
    static let ignoredAppIDs: Set<Int> = [228980]
    /// StateFlags bit Steam sets once a game is fully installed.
    static let fullyInstalled = 4

    public static func steamRoot(in bottle: Bottle) -> URL? {
        let root = bottle.driveC.appending(path: "Program Files (x86)/Steam")
        return FileManager.default.fileExists(atPath: root.appending(path: "steam.exe").path) ? root : nil
    }

    public static func installedGames(in bottle: Bottle) -> [SteamGame] {
        guard let root = steamRoot(in: bottle) else { return [] }
        let fm = FileManager.default
        var games: [Int: SteamGame] = [:]
        for folder in libraryFolders(steamRoot: root, bottle: bottle) {
            let steamapps = folder.appending(path: "steamapps")
            let files = (try? fm.contentsOfDirectory(atPath: steamapps.path)) ?? []
            for file in files where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
                guard let text = try? String(contentsOf: steamapps.appending(path: file), encoding: .utf8),
                      let state = VDF.parse(text)["AppState"],
                      let appID = state["appid"]?.value.flatMap({ Int($0) }),
                      let name = state["name"]?.value,
                      !ignoredAppIDs.contains(appID),
                      let flags = state["StateFlags"]?.value.flatMap({ Int($0) }),
                      flags & fullyInstalled != 0
                else { continue }
                let size = state["SizeOnDisk"]?.value.flatMap { Int64($0) } ?? 0
                games[appID] = SteamGame(appID: appID, name: name, sizeOnDisk: size, artwork: artwork(for: appID, steamRoot: root))
            }
        }
        return games.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func libraryFolders(steamRoot: URL, bottle: Bottle) -> [URL] {
        var folders = [steamRoot]
        let file = steamRoot.appending(path: "steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            let entries = VDF.parse(text)["libraryfolders"]?.children.values.map { $0 } ?? []
            folders += entries.compactMap { $0["path"]?.value }.compactMap(bottle.macURL(forWindowsPath:))
        }
        var seen = Set<String>()
        return folders.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func artwork(for appID: Int, steamRoot: URL) -> URL? {
        let cache = steamRoot.appending(path: "appcache/librarycache")
        let flat = cache.appending(path: "\(appID)_library_600x900.jpg")
        if FileManager.default.fileExists(atPath: flat.path) { return flat }
        // Newer clients keep art in a per-game folder, sometimes nested a level deeper.
        let enumerator = FileManager.default.enumerator(at: cache.appending(path: "\(appID)"), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "library_600x900.jpg" { return url }
        }
        return nil
    }

    public static func remoteArtwork(for appID: Int) -> URL {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg")!
    }
}
