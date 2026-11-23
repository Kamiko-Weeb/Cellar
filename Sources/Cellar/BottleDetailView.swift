import CellarCore
import SwiftUI

struct BottleDetailView: View {
    @Environment(BottleStore.self) private var store
    let bottle: Bottle
    @ViewState private var showingSettings = false

    private var isRunning: Bool { store.running.contains(bottle.id) }
    private var settings: BottleSettings? { store.settings[bottle.id] }
    private var games: [SteamGame] { store.games[bottle.id] ?? [] }
    /// Start Menu shortcuts, minus the main program, which already has the Launch button.
    private var shortcuts: [Shortcut] {
        (store.shortcuts[bottle.id] ?? []).filter { $0.name != settings?.programName }
    }
    private var hasSteam: Bool { SteamLibrary.steamRoot(in: bottle) != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header
                if hasSteam { gamesSection }
                if !shortcuts.isEmpty || !hasSteam { programsSection }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationTitle(bottle.name)
        .sheet(isPresented: $showingSettings) {
            if let settings {
                SettingsSheet(bottle: bottle, settings: settings)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 18) {
                BottleIcon(size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(bottle.name)
                        .font(.display(34))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 10) {
                        StatusPill(isRunning: isRunning)
                        ForEach([bottle.engineName, settings?.graphics.title].compactMap { $0 }, id: \.self) { item in
                            Text("·").foregroundStyle(Theme.hairline)
                            Text(item)
                        }
                    }
                    .font(.meta)
                    .foregroundStyle(Theme.inkMuted)
                }
            }
            actions
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let program = settings?.programName {
                Button {
                    store.launchMain(bottle)
                } label: {
                    Label(isRunning ? "Show \(program)" : "Launch \(program)", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Button {
                store.chooseAndRunProgram(in: bottle)
            } label: {
                Label("Run Program…", systemImage: "arrow.down.app")
            }
            .buttonStyle(QuietButtonStyle())
            .help("Run a Windows installer or .exe in this bottle")
            Button {
                store.showDriveC(bottle)
            } label: {
                Label("C: Drive", systemImage: "internaldrive")
            }
            .buttonStyle(QuietButtonStyle())
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(QuietButtonStyle())
            if isRunning {
                Button {
                    store.stop(bottle)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(QuietButtonStyle(destructive: true))
                .help("Quit everything running in this bottle")
            }
        }
    }

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Games", count: games.count)
            if games.isEmpty {
                EmptyCard(
                    icon: "gamecontroller",
                    title: "No games installed yet",
                    message: "Install a game in Steam and it shows up here, ready to play."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 144, maximum: 176), spacing: 20)], alignment: .leading, spacing: 28) {
                    ForEach(games) { game in
                        GameCard(game: game) { store.play(game, in: bottle) }
                    }
                }
            }
        }
    }

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Programs", count: shortcuts.count)
            if shortcuts.isEmpty {
                EmptyCard(
                    icon: "arrow.down.app",
                    title: "No Windows programs yet",
                    message: "Use Run Program… to install one. Its Start Menu shortcuts appear here."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(shortcuts) { shortcut in
                        ProgramTile(shortcut: shortcut) { store.launch(shortcut, in: bottle) }
                    }
                }
            }
        }
    }
}
