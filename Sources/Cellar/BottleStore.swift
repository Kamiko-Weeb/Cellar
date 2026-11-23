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
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var logTimer: Timer?

    init(polling: Bool = true) {
        reload()
        guard polling else { return }
        startPolling()
        // Keeps Wine logs to a few MB during long sessions. Runs in the background too, but it's one
        // file-size check per bottle with logging on, and nothing at all otherwise.
        logTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capLogs() }
        }
        // Only poll while Cellar is in front, so a game gets the whole Mac.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopPolling() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reload()
                    self?.startPolling()
                }
            },
        ]
    }

    var selectedBottle: Bottle? { bottles.first { $0.id == selection } }

    /// Full scan of every bottle: on launch, on coming back to Cellar, and after actions that change bottles.
    func reload() {
        let found = Bottle.discover(in: Bottle.defaultFolder)
        if found != bottles { bottles = found }
        refreshRunning()
        for bottle in found { scan(bottle) }
        if selectedBottle == nil { selection = found.first?.id }
        capLogs()
    }

    private func startPolling() {
        guard timer == nil else { return }
        // Picks up bottles starting or stopping and games Steam finishes installing in the bottle on screen.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        refreshRunning()
        if let bottle = selectedBottle { scan(bottle) }
    }

    /// The cheap part: one `ps` call.
    private func refreshRunning() {
        let commands = Wine.processCommands()
        let nowRunning = Set(bottles.filter { Wine.isRunning($0, among: commands) }.map(\.id))
        if nowRunning != running { running = nowRunning }
    }

    /// The expensive part: Steam manifests, Start Menu shortcuts, settings and artwork for one bottle.
    private func scan(_ bottle: Bottle) {
        let bottleGames = SteamLibrary.installedGames(in: bottle)
        if games[bottle.id] != bottleGames { games[bottle.id] = bottleGames }
        let bottleShortcuts = Shortcuts.find(in: bottle)
        if shortcuts[bottle.id] != bottleShortcuts { shortcuts[bottle.id] = bottleShortcuts }
        let bottleSettings = try? BottleSettings.load(from: bottle.infoPlist)
        if settings[bottle.id] != bottleSettings { settings[bottle.id] = bottleSettings }
    }

    /// Opened through macOS like a double-click, so the bottle runs under its own
    /// privacy permissions (Documents, removable drives) rather than Cellar's.
    func launchMain(_ bottle: Bottle) {
        // A running bottle is only brought to the front, so its launcher doesn't start over.
        if !running.contains(bottle.id) { preserveLog(of: bottle) }
        NSWorkspace.shared.openApplication(at: bottle.url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in self?.errorMessage = error.localizedDescription }
        }
    }

    func play(_ game: SteamGame, in bottle: Bottle) {
        preserveLog(of: bottle)
        perform { try Wine.play(appID: game.appID, in: bottle) }
    }

    func launch(_ shortcut: Shortcut, in bottle: Bottle) {
        preserveLog(of: bottle)
        perform { try Wine.run(shortcut.url, in: bottle) }
    }

    func chooseAndRunProgram(in bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.message = "Choose a Windows program or installer to run in \(bottle.name)."
        panel.prompt = "Run"
        panel.allowedContentTypes = ["exe", "msi", "bat", "lnk"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preserveLog(of: bottle)
        perform { try Wine.run(url, in: bottle) }
        reload()
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
        preserveLog(of: bottle)
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

    /// Every launcher run empties LastRunWine.log, so copy it aside first when the bottle keeps one.
    private func preserveLog(of bottle: Bottle) {
        if settings[bottle.id]?.logWineOutput == true { WineLog.preserve(bottle) }
    }

    private func capLogs() {
        for bottle in bottles where settings[bottle.id]?.logWineOutput == true {
            WineLog.enforceLimit(bottle)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
