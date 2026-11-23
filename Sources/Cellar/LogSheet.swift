import AppKit
import CellarCore
import SwiftUI

/// The newest Wine log for a bottle, with a summary of what usually explains a crash.
struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    let loggingOn: Bool
    @ViewState private var file: URL?
    @ViewState private var report = WineLogReport(text: "")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wine Log")
                    .font(.display(24))
                    .foregroundStyle(Theme.ink)
                Text(file.map { "\(bottle.name) · \($0.lastPathComponent)" } ?? bottle.name)
                    .font(.meta)
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Group {
                if file == nil {
                    EmptyCard(
                        icon: "doc.text.magnifyingglass",
                        title: loggingOn ? "No log yet" : "Logging is off",
                        message: loggingOn
                            ? "Run a game or program in this bottle. Wine's errors show up here."
                            : "Turn on Log Wine output in Settings, then run the game again."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        summary
                        lines
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 8) {
                Button("Show in Finder") {
                    if let file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                }
                .disabled(file == nil)
                Button("Clear") {
                    WineLog.clear(bottle)
                    load()
                }
                .buttonStyle(QuietButtonStyle(destructive: true))
                .disabled(file == nil)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(QuietButtonStyle())
            .padding(24)
        }
        .frame(width: 780, height: 580)
        .background(Theme.canvas)
        .onAppear(perform: load)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.summary.isEmpty {
                Label("Nothing here that usually explains a crash.", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.ok)
            } else {
                ForEach(report.summary, id: \.self) { item in
                    Label(item, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.accent)
                        .textSelection(.enabled)
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(report.summary.isEmpty ? Theme.okPale : Theme.accentPale, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private var lines: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(report.lines) { line in
                    LogLineRow(line: line)
                }
            }
            .padding(.vertical, 8)
            .textSelection(.enabled)
        }
        .defaultScrollAnchor(.bottom)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.hairline))
    }

    private func load() {
        file = WineLog.newest(for: bottle)
        report = WineLogReport(text: file.map(WineLog.read) ?? "")
    }
}

private struct LogLineRow: View {
    let line: WineLogReport.Line

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(tag)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, alignment: .leading)
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(line.kind.matters ? Theme.ink : line.kind == .noise ? Theme.inkMuted.opacity(0.6) : Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.kind.matters ? Theme.accentPale : .clear)
    }

    private var tag: String {
        switch line.kind {
        case .module: "DLL"
        case .graphics: "GPU"
        case .unimplemented: "STUB"
        case .pageFault: "CRASH"
        case .plain, .noise: ""
        }
    }
}
