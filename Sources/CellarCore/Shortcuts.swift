import Foundation

/// A Start Menu shortcut left behind by a Windows installer.
public struct Shortcut: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: URL

    public var id: URL { url }
}

public enum Shortcuts {
    public static func find(in bottle: Bottle) -> [Shortcut] {
        let fm = FileManager.default
        let startMenu = "Microsoft/Windows/Start Menu/Programs"
        var roots = [bottle.driveC.appending(path: "ProgramData/\(startMenu)")]
        let users = bottle.driveC.appending(path: "users")
        for user in (try? fm.contentsOfDirectory(atPath: users.path)) ?? [] {
            roots.append(users.appending(path: "\(user)/AppData/Roaming/\(startMenu)"))
        }

        var byName: [String: Shortcut] = [:]
        for root in roots {
            let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "lnk" else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                guard !name.lowercased().contains("uninstall") else { continue }
                byName[name] = byName[name] ?? Shortcut(name: name, url: url)
            }
        }
        return byName.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
