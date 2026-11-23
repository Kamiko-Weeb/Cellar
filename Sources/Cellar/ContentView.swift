import CellarCore
import SwiftUI

struct ContentView: View {
    @Environment(BottleStore.self) private var store
    @ViewState private var showingNewBottle = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $store.selection) {
                Section {
                    ForEach(store.bottles) { bottle in
                        BottleRow(bottle: bottle, isRunning: store.running.contains(bottle.id))
                            .tag(bottle.id)
                    }
                } header: {
                    Text("Bottles")
                        .font(.label)
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .toolbar {
                ToolbarItem {
                    Button {
                        showingNewBottle = true
                    } label: {
                        Label("New Bottle", systemImage: "plus")
                    }
                    .help("Create a new bottle for another Windows app")
                }
            }
        } detail: {
            if let bottle = store.selectedBottle {
                BottleDetailView(bottle: bottle)
                    .id(bottle.id)
            } else {
                EmptyLibrary { showingNewBottle = true }
            }
        }
        .sheet(isPresented: $showingNewBottle) {
            NewBottleSheet()
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct BottleRow: View {
    let bottle: Bottle
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            BottleIcon(size: 24)
            Text(bottle.name)
                .font(.system(size: 13))
            Spacer()
            if isRunning {
                Circle()
                    .fill(Theme.ok)
                    .frame(width: 7, height: 7)
                    .help("Running")
            }
        }
        .padding(.vertical, 2)
    }
}

/// A flat tile with a thin wineglass: the one place the accent color is allowed to be loud.
struct BottleIcon: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Theme.accentPale)
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(Theme.hairline))
            .overlay {
                Image(systemName: "wineglass")
                    .font(.system(size: size * 0.46, weight: .regular))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: size, height: size)
    }
}

private struct EmptyLibrary: View {
    let create: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            BottleIcon(size: 56)
            Text("No bottles yet")
                .font(.display(26))
                .foregroundStyle(Theme.ink)
            Text("A bottle is a separate Windows environment for an app or game.")
                .foregroundStyle(Theme.inkMuted)
            Button("New Bottle", action: create)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}
