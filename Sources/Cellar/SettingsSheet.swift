import CellarCore
import SwiftUI

struct SettingsSheet: View {
    @Environment(BottleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @ViewState private var settings: BottleSettings

    init(bottle: Bottle, settings: BottleSettings) {
        self.bottle = bottle
        _settings = State(initialValue: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                BottleIcon(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bottle.name)
                        .font(.display(24))
                        .foregroundStyle(Theme.ink)
                    Text(bottle.engineName ?? "Wine")
                        .font(.meta)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 28) {
                group("Graphics") {
                    Picker("Translator", selection: $settings.graphics) {
                        ForEach(settings.availableBackends) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.graphics.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                group("Performance") {
                    toggleRow("Show FPS overlay", detail: "Apple's Metal HUD in the game's corner.", isOn: $settings.metalHUD)
                    divider
                    toggleRow("MSync", detail: "Faster thread syncing. Leave on unless a game freezes.", isOn: $settings.msync)
                }
                group("Tools") {
                    toggleRow("Log Wine output", detail: "Keeps Wine's errors so Logs can show why a game crashed.", isOn: $settings.logWineOutput)
                    divider
                    HStack {
                        Text("Main program")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(settings.programPath.isEmpty ? "None" : settings.programPath)
                            .font(.meta)
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    divider
                    HStack(spacing: 8) {
                        Button("Wine Configuration") { store.openWineConfiguration(bottle) }
                        Button("Advanced Settings") { store.openAdvancedSettings(bottle) }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .padding(.horizontal, 24)

            HStack {
                if store.running.contains(bottle.id) {
                    Text("Changes apply the next time this bottle starts.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.save(settings, for: bottle)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(width: 520)
        .background(Theme.canvas)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.label)
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkMuted)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
