import CellarCore
import SwiftUI

struct NewBottleSheet: View {
    @Environment(BottleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var status: String?
    @ViewState private var error: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var runningBottles: [Bottle] { store.bottles.filter { store.running.contains($0.id) } }
    private var runningNames: String { runningBottles.map(\.name).formatted(.list(type: .and)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                BottleIcon(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Bottle")
                        .font(.display(24))
                        .foregroundStyle(Theme.ink)
                    Text("A separate Windows environment for an app or game.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            TextField("Name, like Office or Epic Games", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).strokeBorder(Theme.hairline))
                .disabled(status != nil)
                .onSubmit(create)
            if status == nil, !runningBottles.isEmpty {
                // Sikarugir only finishes setting up a bottle once no other bottle is running.
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(runningNames) needs to close first. Wine can only set up a new bottle while no other bottle is open.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Stop \(runningNames)") { runningBottles.forEach(store.stop) }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(14)
                .background(Theme.accentPale, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            }
            if let status {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(status != nil)
                Button("Create", action: create)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || status != nil || !runningBottles.isEmpty)
                    .opacity(trimmedName.isEmpty || status != nil || !runningBottles.isEmpty ? 0.5 : 1)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.canvas)
    }

    private func create() {
        guard status == nil, !trimmedName.isEmpty else { return }
        error = nil
        status = "Starting…"
        Task {
            do {
                try await store.createBottle(named: trimmedName) { status = $0 }
                dismiss()
            } catch {
                self.error = error.localizedDescription
                status = nil
            }
        }
    }
}
