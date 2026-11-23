import CellarCore
import SwiftUI

struct GameCard: View {
    let game: SteamGame
    let play: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 10) {
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay { Poster(game: game) }
                    .overlay {
                        ZStack {
                            Theme.ink.opacity(0.35)
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 48, height: 48)
                                .background(Theme.canvas, in: Circle())
                        }
                        .opacity(hovering ? 1 : 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.hairline))
                    .shadow(color: .black.opacity(hovering ? 0.10 : 0), radius: 10, y: 4)
                    .offset(y: hovering ? -2 : 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: game.sizeOnDisk, countStyle: .file))
                        .font(.meta)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.2)) { hovering = isHovering }
        }
        .help("Play \(game.name)")
    }
}

/// Steam's cached poster art, falling back to Steam's CDN, then to a typographic tile.
private struct Poster: View {
    let game: SteamGame

    var body: some View {
        if let file = game.artwork, let image = NSImage(contentsOf: file) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            AsyncImage(url: SteamLibrary.remoteArtwork(for: game.appID)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack(alignment: .bottomLeading) {
                        Theme.surfaceRaised
                        Text(game.name)
                            .font(.display(18))
                            .foregroundStyle(Theme.ink)
                            .padding(14)
                    }
                }
            }
        }
    }
}

struct ProgramTile: View {
    let shortcut: Shortcut
    let run: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: "macwindow")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentPale, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                Text(shortcut.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Theme.surfaceRaised : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.hairline))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Open \(shortcut.name)")
    }
}

struct StatusPill: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Theme.ok : Theme.inkMuted)
                .frame(width: 6, height: 6)
            Text(isRunning ? "Running" : "Stopped")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(isRunning ? Theme.ok : Theme.inkMuted)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(isRunning ? Theme.okPale : Theme.surfaceRaised, in: Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.label)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkMuted)
                if count > 0 {
                    Text("\(count)")
                        .font(.meta)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
    }
}

struct EmptyCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accentPale, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.hairline))
    }
}
