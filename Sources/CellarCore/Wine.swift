import Foundation

/// Runs things inside a bottle through the wrapper's own launcher, so every program
/// gets the wrapper's environment (D3DMetal, MSync, library paths).
///
/// The launcher speaks the old Wineskin command line: no arguments runs the main program,
/// a file path runs that file, and `WSS-…` commands do maintenance. It passes no extra
/// arguments through to programs, so anything that needs arguments goes through a small
/// batch file written inside the bottle.
public enum Wine {
    static let steamExe = #"C:\Program Files (x86)\Steam\steam.exe"#

    /// Steam hands `-applaunch` to its running instance, so this works whether Steam is open or not.
    public static func play(appID: Int, in bottle: Bottle) throws {
        try runScript(named: "play-\(appID)", #"start "" "\#(steamExe)" -applaunch \#(appID)"#, in: bottle)
    }

    /// Opens a program, installer or shortcut. Windows' `start` handles every kind (and paths
    /// with spaces, which the launcher can't take), starting in the file's own folder.
    public static func run(_ file: URL, in bottle: Bottle) throws {
        // Batch files expand %…% even inside quotes, so "setup%20v2.exe" would lose its %2.
        let folder = windowsPath(for: file.deletingLastPathComponent()).replacingOccurrences(of: "%", with: "%%")
        let path = windowsPath(for: file).replacingOccurrences(of: "%", with: "%%")
        try runScript(named: "run-program", #"start "" /d "\#(folder)" "\#(path)""#, in: bottle)
    }

    public static func openWineConfiguration(_ bottle: Bottle) throws {
        try start(bottle, ["WSS-winecfg"])
    }

    public static func stop(_ bottle: Bottle) async throws {
        _ = try await runToCompletion(bottle.launcher, ["WSS-wineserverkill"])
    }

    /// Every running process's command line, for `isRunning`.
    public static func processCommands() -> [String] {
        let process = makeProcess(URL(fileURLWithPath: "/bin/ps"), ["-axo", "command="])
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A bottle is running while its wineserver is alive.
    public static func isRunning(_ bottle: Bottle, among commands: [String]) -> Bool {
        let engine = bottle.contents.path + "/SharedSupport/wine/"
        return commands.contains { $0.hasPrefix(engine) && $0.hasSuffix("wineserver") }
    }

    /// Wine maps the Mac's root folder to Z:, so every Mac file has a Windows path.
    static func windowsPath(for url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return "Z:" + path.replacingOccurrences(of: "/", with: #"\"#)
    }

    static func runScript(named name: String, _ command: String, in bottle: Bottle) throws {
        let folder = bottle.driveC.appending(path: "cellar")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appending(path: "\(name).bat")
        try "@echo off\r\n\(command)\r\n".write(to: script, atomically: true, encoding: .utf8)
        try start(bottle, [script.path(percentEncoded: false)])
    }

    static func start(_ bottle: Bottle, _ arguments: [String]) throws {
        try makeProcess(bottle.launcher, arguments).run()
    }

    static func runToCompletion(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = makeProcess(executable, arguments)
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func makeProcess(_ executable: URL, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Keep loader overrides (test runners set DYLD_FRAMEWORK_PATH) away from Wine.
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") }
        return process
    }
}
