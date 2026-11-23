import Foundation

/// How DirectX calls get translated to Metal.
public enum GraphicsBackend: String, CaseIterable, Identifiable, Sendable {
    case d3dMetal
    case dxmt
    case dxvk
    case wineD3D

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wineD3D: "WineD3D"
        }
    }

    public var summary: String {
        switch self {
        case .d3dMetal: "Apple's translator. Best for DirectX 12 games."
        case .dxmt: "Turns DirectX 10 and 11 straight into Metal. Needed for Rockstar's launcher (GTA V)."
        case .dxvk: "DirectX 9–11 through Vulkan. Often best for older games."
        case .wineD3D: "Wine's built-in renderer. Most compatible, but the slowest."
        }
    }

    /// The Info.plist switch for this backend in older wrappers, where WineD3D is what's left when all are off.
    var plistKey: String? {
        switch self {
        case .d3dMetal: "D3DMETAL"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wineD3D: nil
        }
    }

    static let plistKeys = ["D3DMETAL", "DXMT", "DXVK", "D9VK"]
}

/// The handful of wrapper settings Cellar exposes, stored in the wrapper's Info.plist.
///
/// Wrappers come in two layouts. Older templates (before about 1.0.20) have a switch per
/// renderer, including DXMT, and fall back to WineD3D when all are off. Newer ones have no
/// DXMT switch: DXMT is the default unless the D3DMetal or DXVK switch is on.
public struct BottleSettings: Equatable, Sendable {
    public var graphics: GraphicsBackend
    public var metalHUD: Bool
    public var msync: Bool
    public var programPath: String
    /// The renderers this wrapper's layout can select.
    public var availableBackends: [GraphicsBackend]

    public init(
        graphics: GraphicsBackend,
        metalHUD: Bool,
        msync: Bool,
        programPath: String,
        availableBackends: [GraphicsBackend] = GraphicsBackend.allCases
    ) {
        self.graphics = graphics
        self.metalHUD = metalHUD
        self.msync = msync
        self.programPath = programPath
        self.availableBackends = availableBackends
    }

    /// The main program's name ("Steam"), or nil when the wrapper has none set.
    public var programName: String? {
        let file = programPath.split(separator: "/").last.map(String.init) ?? ""
        guard !file.isEmpty, file.lowercased() != "nothing.exe" else { return nil }
        return (file as NSString).deletingPathExtension
    }

    public static func load(from url: URL) throws -> BottleSettings {
        let (dict, _) = try read(url)
        func flag(_ key: String) -> Bool { (dict[key] as? NSNumber)?.boolValue ?? false }
        let hasDXMTSwitch = dict["DXMT"] != nil
        let graphics: GraphicsBackend
        if flag("D3DMETAL") {
            graphics = .d3dMetal
        } else if hasDXMTSwitch {
            graphics = flag("DXMT") ? .dxmt : flag("DXVK") ? .dxvk : .wineD3D
        } else {
            graphics = flag("DXVK") ? .dxvk : .dxmt
        }
        return BottleSettings(
            graphics: graphics,
            metalHUD: flag("METAL_HUD"),
            msync: flag("WINEMSYNC"),
            programPath: dict["Program Name and Path"] as? String ?? "",
            availableBackends: hasDXMTSwitch ? GraphicsBackend.allCases : [.d3dMetal, .dxmt, .dxvk]
        )
    }

    public func save(to url: URL) throws {
        try Self.edit(url) { dict in
            if dict["DXMT"] != nil {
                for key in GraphicsBackend.plistKeys {
                    dict[key] = key == graphics.plistKey ? 1 : 0
                }
            } else {
                // DXMT is the default here. D9VK (DirectX 9 only) is a separate switch, left as it is.
                dict["D3DMETAL"] = graphics == .d3dMetal ? 1 : 0
                dict["DXVK"] = graphics == .dxvk ? 1 : 0
            }
            dict["METAL_HUD"] = metalHUD ? 1 : 0
            dict["WINEMSYNC"] = msync ? 1 : 0
        }
    }

    /// Reads the plist, lets `body` change it, and writes it back in its original format.
    static func edit(_ url: URL, _ body: (inout [String: Any]) -> Void) throws {
        var (dict, format) = try read(url)
        body(&dict)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private static func read(_ url: URL) throws -> ([String: Any], PropertyListSerialization.PropertyListFormat) {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let data = try Data(contentsOf: url)
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return (dict, format)
    }
}
