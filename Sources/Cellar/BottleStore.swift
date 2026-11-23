import AppKit
import CellarCore
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class BottleStore {
    private(set) var bottles: [Bottle] = []
    var selection: Bottle.ID?
    private(set) var running: Set<Bottle.ID> = []
    private(set) var games: [Bottle.ID: [SteamGame]] = [:]
    private(set) var shortcuts: [Bottle.ID: [Shortcut]] = [:]
    private(set) var settings: [Bottle.ID: BottleSettings] = [:]
    var errorMessage: String?
    @ObservationIgnored private var timer: Timer?

    init(polling: Bool = true) {
        reload()
        guard polling else { return }
        // Cheap enough to rescan: picks up games Steam finishes installing and bottles starting or stopping.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var selectedBottle: Bottle? { bottles.first { $0.id == selection } }

    func reload() {
        let found = Bottle.discover(in: Bottle.defaultFolder)
        if found != bottles { bottles = found }
        let commands = Wine.processCommands()
        let nowRunning = Set(found.filter { Wine.isRunning($0, among: commands) }.map(\.id))
        if nowRunning != running { running = nowRunning }
        for bottle in found {
            let bottleGames = SteamLibrary.installedGames(in: bottle)
            if games[bottle.id] != bottleGames { games[bottle.id] = bottleGames }
            let bottleShortcuts = Shortcuts.find(in: bottle)
            if shortcuts[bottle.id] != bottleShortcuts { shortcuts[bottle.id] = bottleShortcuts }
            let bottleSettings = try? BottleSettings.load(from: bottle.infoPlist)
            if settings[bottle.id] != bottleSettings { settings[bottle.id] = bottleSettings }
        }
        if selectedBottle == nil { selection = found.first?.id }
    }

    /// Opened through macOS like a double-click, so the bottle runs under its own
    /// privacy permissions (Documents, removable drives) rather than Cellar's.
    func launchMain(_ bottle: Bottle) {
        NSWorkspace.shared.openApplication(at: bottle.url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in self?.errorMessage = error.localizedDescription }
        }
    }

    func play(_ game: SteamGame, in bottle: Bottle) {
        perform { try Wine.play(appID: game.appID, in: bottle) }
    }

    func launch(_ shortcut: Shortcut, in bottle: Bottle) {
        perform { try Wine.run(shortcut.url, in: bottle) }
    }

    func chooseAndRunProgram(in bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.message = "Choose a Windows program or installer to run in \(bottle.name)."
        panel.prompt = "Run"
        panel.allowedContentTypes = ["exe", "msi", "bat", "lnk"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try Wine.run(url, in: bottle) }
    }

    func stop(_ bottle: Bottle) {
        Task {
            do {
                try await Wine.stop(bottle)
            } catch {
                errorMessage = error.localizedDescription
            }
            reload()
        }
    }

    func showDriveC(_ bottle: Bottle) {
        NSWorkspace.shared.open(bottle.driveC)
    }

    func save(_ newSettings: BottleSettings, for bottle: Bottle) {
        perform { try newSettings.save(to: bottle.infoPlist) }
        settings[bottle.id] = newSettings
    }

    func openWineConfiguration(_ bottle: Bottle) {
        perform { try Wine.openWineConfiguration(bottle) }
    }

    /// Sikarugir's own settings window, which ships inside every wrapper.
    func openAdvancedSettings(_ bottle: Bottle) {
        NSWorkspace.shared.open(bottle.contents.appending(path: "Configure.app"))
    }

    func createBottle(named name: String, status: @escaping @MainActor @Sendable (String) -> Void) async throws {
        let bottle = try await BottleFactory.create(named: name, status: status)
        reload()
        selection = bottle.id
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
