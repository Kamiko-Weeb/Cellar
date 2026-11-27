import Foundation

/// Builds a new bottle from Sikarugir's empty wrapper template plus a Wine engine.
/// Wine 11 is the first engine Rockstar's launcher (GTA V) works on.
public enum BottleFactory {
    static let engineName = "WS12WineSikarugir11.0_1"
    static let engineURL = URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz")!
    static let templateName = "Template-1.0.27"
    static let templateURL = URL(string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.27.tar.xz")!

    public enum Failure: LocalizedError, Equatable {
        case invalidName
        case alreadyExists(String)
        case otherBottleRunning
        case setupFailed

        public var errorDescription: String? {
            switch self {
            case .invalidName: "Pick a name without slashes."
            case .alreadyExists(let name): "There's already a bottle called \(name)."
            case .otherBottleRunning: "Close every other bottle first. Wine can only set up a new bottle while no other bottle is open."
            case .setupFailed: "Wine couldn't set up Windows in the new bottle."
            }
        }
    }

    public static func create(
        named rawName: String,
        in folder: URL = Bottle.defaultFolder,
        status: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) async throws -> Bottle {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else { throw Failure.invalidName }
        let fm = FileManager.default
        let destination = folder.appending(path: "\(folderName(for: name)).app")
        let taken = Bottle.discover(in: folder).contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        guard !taken, !fm.fileExists(atPath: destination.path) else { throw Failure.alreadyExists(name) }

        await status("Getting Wine…")
        let engine = try await cached(engineURL, as: "Engines/\(engineName).tar.xz")
        let template = try await cached(templateURL, as: "Template/\(templateName).tar.xz")

        await status("Building the bottle…")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let scratch = fm.temporaryDirectory.appending(path: UUID().uuidString)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let bottle = Bottle(url: destination)
        do {
            try await untar(template, into: scratch)
            try fm.copyItem(at: scratch.appending(path: "\(templateName).app"), to: destination)
            let support = destination.appending(path: "Contents/SharedSupport")
            try await untar(engine, into: support)
            try fm.moveItem(at: support.appending(path: "wswine.bundle"), to: support.appending(path: "wine"))
            // The template's renderer default (DXMT) is kept: Rockstar's launcher doesn't start under D3DMetal.
            try BottleSettings.edit(bottle.infoPlist) { dict in
                dict[Bottle.nameKey] = name
                dict["CFBundleName"] = name
                dict["Skip Gecko"] = 1
                dict["Skip Mono"] = 1
                // The template ships with Wine's DLL-load logging on, which only costs speed.
                dict["WINEDEBUG"] = "-all"
                // Lets macOS treat the bottle as a game (Game Mode when fullscreen).
                dict["LSApplicationCategoryType"] = "public.app-category.games"
            }
        } catch {
            // Nothing inside links out of the bottle yet, so removing the half-built copy is safe.
            try? fm.removeItem(at: destination)
            throw error
        }

        // The launcher's setup step waits (forever) until no wineserver is running anywhere on the Mac,
        // so check right before it, not before the download, when a bottle may still be opened.
        guard !Wine.processCommands().contains(where: { $0.hasSuffix("/wineserver") }) else {
            try? fm.removeItem(at: destination)
            throw Failure.otherBottleRunning
        }
        await status("Setting up Windows… (about a minute)")
        _ = try await Wine.runToCompletion(bottle.launcher, ["WSS-wineprefixcreate"])
        guard fm.fileExists(atPath: bottle.driveC.appending(path: "Program Files (x86)").path) else {
            // removeItem deletes the prefix's links to your folders, never the folders they point at.
            try? fm.removeItem(at: destination)
            throw Failure.setupFailed
        }
        return Bottle(url: destination)
    }

    /// Sikarugir's launcher never exits when its wrapper's path contains a space, so folder
    /// names keep only letters, digits, `-` and `_`. The display name is stored separately.
    static func folderName(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let kept = String(String.UnicodeScalarView(name.unicodeScalars.filter { allowed.contains($0) && $0.isASCII }))
        return kept.isEmpty ? "Bottle" : kept
    }

    static var cacheFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Sikarugir")
    }

    /// Reuses Sikarugir's own download cache, so the engine is only downloaded once.
    static func cached(_ remote: URL, as relativePath: String) async throws -> URL {
        let local = cacheFolder.appending(path: relativePath)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (downloaded, response) = try await URLSession.shared.download(from: remote)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try FileManager.default.moveItem(at: downloaded, to: local)
        return local
    }

    static func untar(_ archive: URL, into folder: URL) async throws {
        let status = try await Wine.runToCompletion(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", archive.path, "-C", folder.path])
        guard status == 0 else { throw CocoaError(.fileReadCorruptFile) }
    }
}
