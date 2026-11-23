import AppKit
import SwiftUI

/// `Cellar --snapshot out.png` renders the window and the sheets to PNGs, in light and dark
/// appearance, without putting anything on screen.
@MainActor
enum Snapshot {
    static func render(to url: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let store = BottleStore(polling: false)
        let base = url.deletingPathExtension().path
        for (suffix, appearance) in [("", NSAppearance.Name.aqua), ("-dark", .darkAqua)] {
            let main = CGSize(width: 1120, height: 740)
            for bottle in store.bottles {
                store.selection = bottle.id
                write(ContentView(), store: store, size: main, appearance: appearance, to: URL(fileURLWithPath: "\(base)-\(bottle.name)\(suffix).png"))
            }
            if let bottle = store.bottles.last, let settings = store.settings[bottle.id] {
                write(SettingsSheet(bottle: bottle, settings: settings), store: store, size: CGSize(width: 520, height: 620), appearance: appearance, to: URL(fileURLWithPath: "\(base)-settings\(suffix).png"))
            }
            if let bottle = store.bottles.first {
                write(LogSheet(bottle: bottle, loggingOn: store.settings[bottle.id]?.logWineOutput ?? false), store: store, size: CGSize(width: 780, height: 580), appearance: appearance, to: URL(fileURLWithPath: "\(base)-logs\(suffix).png"))
            }
            write(NewBottleSheet(), store: store, size: CGSize(width: 460, height: 200), appearance: appearance, to: URL(fileURLWithPath: "\(base)-new-bottle\(suffix).png"))
        }
        exit(0)
    }

    private static func write(_ view: some View, store: BottleStore, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let root = view
            .environment(store)
            .tint(Theme.accent)
            .frame(width: size.width, height: size.height)
            .background(Theme.canvas)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.layoutIfNeeded()
        // Give layout and remote poster images a moment to arrive.
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
