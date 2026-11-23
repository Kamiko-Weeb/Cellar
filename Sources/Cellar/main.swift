import AppKit

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    MainActor.assumeIsolated { Snapshot.render(to: URL(fileURLWithPath: arguments[index + 1])) }
} else {
    CellarApp.main()
}
