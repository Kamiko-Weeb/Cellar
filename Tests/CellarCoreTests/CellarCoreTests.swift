import Foundation
import Testing
@testable import CellarCore

/// A throwaway bottle laid out like a real Sikarugir wrapper.
struct BottleFixture {
    let root: URL
    let bottle: Bottle

    init(name: String = "Steam") throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appending(path: "cellar-tests-\(UUID().uuidString)")
        bottle = Bottle(url: root.appending(path: "\(name).app"))
        try fm.createDirectory(at: bottle.contents.appending(path: "SharedSupport/wine"), withIntermediateDirectories: true)
        try fm.createDirectory(at: bottle.driveC, withIntermediateDirectories: true)
        try fm.createDirectory(at: bottle.contents.appending(path: "dosdevices"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: bottle.contents.appending(path: "dosdevices/c:").path, withDestinationPath: "../drive_c")
        try fm.createSymbolicLink(atPath: bottle.contents.appending(path: "dosdevices/z:").path, withDestinationPath: "/")
        try "wine sikarugir 10.0 (revision 6)\n".write(to: bottle.contents.appending(path: "SharedSupport/wine/version"), atomically: true, encoding: .utf8)
    }

    func write(_ text: String, to relativePath: String, under base: URL? = nil) throws {
        let url = (base ?? bottle.driveC).appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func manifest(appID: Int, name: String, flags: Int) -> String {
        """
        "AppState"
        {
            "appid"        "\(appID)"
            "name"         "\(name)"
            "StateFlags"   "\(flags)"
            "installdir"   "\(name)"
            "SizeOnDisk"   "1048576"
        }
        """
    }
}

struct VDFTests {
    @Test func parsesNestedObjectsEscapesAndComments() {
        let text = #"""
        // written by Steam
        "libraryfolders"
        {
            "0"
            {
                "path"      "C:\\Program Files (x86)\\Steam"
                "apps" { "228980" "123" }
            }
            "1" { "path" "Z:\\Volumes\\Games\\SteamLibrary" }
        }
        """#
        let root = VDF.parse(text)
        #expect(root["LibraryFolders"]?["0"]?["path"]?.value == #"C:\Program Files (x86)\Steam"#)
        #expect(root["libraryfolders"]?["0"]?["apps"]?["228980"]?.value == "123")
        #expect(root["libraryfolders"]?["1"]?["path"]?.value == #"Z:\Volumes\Games\SteamLibrary"#)
    }
}

struct BottleTests {
    @Test func mapsWindowsPathsThroughDriveLinks() throws {
        let fixture = try BottleFixture()
        let bottle = fixture.bottle
        #expect(bottle.macURL(forWindowsPath: #"C:\Program Files (x86)\Steam"#)?.path == bottle.driveC.appending(path: "Program Files (x86)/Steam").path)
        #expect(bottle.macURL(forWindowsPath: #"Z:\Volumes\Games"#)?.path == "/Volumes/Games")
        #expect(bottle.macURL(forWindowsPath: #"Q:\nowhere"#) == nil)
        #expect(bottle.macURL(forWindowsPath: "relative") == nil)
    }

    /// Sikarugir's real drive letters live in SharedSupport/prefix/dosdevices; a stray Contents/dosdevices must not win.
    @Test func readsDriveLettersFromTheSikarugirPrefix() throws {
        let fixture = try BottleFixture()
        let fm = FileManager.default
        let prefixDevices = fixture.bottle.contents.appending(path: "SharedSupport/prefix/dosdevices")
        try fm.createDirectory(at: prefixDevices, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: prefixDevices.appending(path: "d:").path, withDestinationPath: "/Volumes/Extreme SSD")
        try fm.createSymbolicLink(atPath: fixture.bottle.contents.appending(path: "dosdevices/d:").path, withDestinationPath: "/Volumes/Wrong")

        #expect(fixture.bottle.prefix.lastPathComponent == "prefix")
        #expect(fixture.bottle.macURL(forWindowsPath: #"D:\SteamLibrary"#)?.path == "/Volumes/Extreme SSD/SteamLibrary")
    }

    @Test func discoversOnlyWrappersAndReadsEngine() throws {
        let fixture = try BottleFixture()
        try FileManager.default.createDirectory(at: fixture.root.appending(path: "NotABottle.app"), withIntermediateDirectories: true)
        #expect(Bottle.discover(in: fixture.root).map(\.name) == ["Steam"])
        #expect(fixture.bottle.engineName == "Wine 10.0")
    }
}

struct SteamLibraryTests {
    @Test func findsFullyInstalledGamesAcrossLibraries() throws {
        let fixture = try BottleFixture()
        let external = fixture.root.appending(path: "ExternalLibrary")
        let externalWindowsPath = "Z:" + external.path.replacingOccurrences(of: "/", with: #"\\"#)
        let steam = "Program Files (x86)/Steam"
        try fixture.write("", to: "\(steam)/steam.exe")
        try fixture.write("""
        "libraryfolders"
        {
            "0" { "path" "C:\\\\Program Files (x86)\\\\Steam" }
            "1" { "path" "\(externalWindowsPath)" }
        }
        """, to: "\(steam)/steamapps/libraryfolders.vdf")
        try fixture.write(fixture.manifest(appID: 271590, name: "Grand Theft Auto V Legacy", flags: 4), to: "\(steam)/steamapps/appmanifest_271590.acf")
        try fixture.write(fixture.manifest(appID: 228980, name: "Steamworks Common Redistributables", flags: 4), to: "\(steam)/steamapps/appmanifest_228980.acf")
        try fixture.write(fixture.manifest(appID: 1091500, name: "Still Downloading", flags: 1026), to: "\(steam)/steamapps/appmanifest_1091500.acf")
        try fixture.write(fixture.manifest(appID: 620, name: "Portal 2", flags: 4), to: "steamapps/appmanifest_620.acf", under: external)
        try fixture.write("", to: "\(steam)/appcache/librarycache/271590/library_600x900.jpg")

        let games = SteamLibrary.installedGames(in: fixture.bottle)
        #expect(games.map(\.name) == ["Grand Theft Auto V Legacy", "Portal 2"])
        #expect(games.first?.artwork?.lastPathComponent == "library_600x900.jpg")
        #expect(games.last?.artwork == nil)
        #expect(games.first?.sizeOnDisk == 1_048_576)
    }

    @Test func skipsLibrariesOnDrivesThatAreUnplugged() throws {
        let fixture = try BottleFixture()
        let steam = "Program Files (x86)/Steam"
        let unplugged = fixture.root.appending(path: "Volumes/Extreme SSD")
        // D: still points at the SSD's mount point, but the SSD isn't there. E: has no drive link at all.
        try FileManager.default.createSymbolicLink(atPath: fixture.bottle.contents.appending(path: "dosdevices/d:").path, withDestinationPath: unplugged.path)
        try fixture.write("", to: "\(steam)/steam.exe")
        try fixture.write("""
        "libraryfolders"
        {
            "0" { "path" "C:\\\\Program Files (x86)\\\\Steam" }
            "1" { "path" "D:\\\\SteamLibrary" }
            "2" { "path" "E:\\\\Games" }
        }
        """, to: "\(steam)/steamapps/libraryfolders.vdf")
        try fixture.write(fixture.manifest(appID: 620, name: "Portal 2", flags: 4), to: "\(steam)/steamapps/appmanifest_620.acf")

        let root = try #require(SteamLibrary.steamRoot(in: fixture.bottle))
        #expect(SteamLibrary.libraryFolders(steamRoot: root, bottle: fixture.bottle) == [root])
        #expect(SteamLibrary.installedGames(in: fixture.bottle).map(\.name) == ["Portal 2"])
    }

    @Test func bottleWithoutSteamHasNoGames() throws {
        let fixture = try BottleFixture(name: "Office")
        #expect(SteamLibrary.steamRoot(in: fixture.bottle) == nil)
        #expect(SteamLibrary.installedGames(in: fixture.bottle).isEmpty)
    }
}

struct BottleSettingsTests {
    @Test func savesBackendSwitchesAndKeepsOtherKeys() throws {
        let fixture = try BottleFixture()
        let plist: [String: Any] = [
            "D3DMETAL": 1, "DXMT": 0, "DXVK": 0, "D9VK": 0, "METAL_HUD": 0, "WINEMSYNC": 1,
            "Program Name and Path": "/Program Files (x86)/Steam/Steam.exe", "Untouched": "keep me",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: fixture.bottle.infoPlist)

        var settings = try BottleSettings.load(from: fixture.bottle.infoPlist)
        #expect(settings.graphics == .d3dMetal)
        #expect(settings.msync)
        #expect(!settings.metalHUD)
        #expect(settings.programName == "Steam")

        settings.graphics = .dxmt
        settings.metalHUD = true
        try settings.save(to: fixture.bottle.infoPlist)

        let raw = try PropertyListSerialization.propertyList(from: Data(contentsOf: fixture.bottle.infoPlist), format: nil) as! [String: Any]
        #expect(raw["DXMT"] as? Int == 1)
        #expect(raw["D3DMETAL"] as? Int == 0)
        #expect(raw["METAL_HUD"] as? Int == 1)
        #expect(raw["Untouched"] as? String == "keep me")
        #expect(try BottleSettings.load(from: fixture.bottle.infoPlist) == settings)
    }

    /// Templates from about 1.0.20 on: no DXMT switch, DXMT unless D3DMetal or DXVK is on.
    @Test func newerWrappersDefaultToDXMTAndKeepD9VK() throws {
        let fixture = try BottleFixture()
        let plist: [String: Any] = ["D3DMETAL": 0, "DXVK": 0, "D9VK": 1, "METAL_HUD": 0, "WINEMSYNC": 1, "Program Name and Path": "/nothing.exe"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: fixture.bottle.infoPlist)
        func raw() throws -> [String: Any] {
            try PropertyListSerialization.propertyList(from: Data(contentsOf: fixture.bottle.infoPlist), format: nil) as! [String: Any]
        }

        var settings = try BottleSettings.load(from: fixture.bottle.infoPlist)
        #expect(settings.graphics == .dxmt)
        #expect(settings.availableBackends == [.d3dMetal, .dxmt, .dxvk])

        settings.graphics = .dxvk
        try settings.save(to: fixture.bottle.infoPlist)
        #expect(try raw()["DXVK"] as? Int == 1)
        #expect(try raw()["D3DMETAL"] as? Int == 0)
        #expect(try raw()["DXMT"] == nil)
        #expect(try raw()["D9VK"] as? Int == 1)

        settings.graphics = .dxmt
        try settings.save(to: fixture.bottle.infoPlist)
        #expect(try BottleSettings.load(from: fixture.bottle.infoPlist).graphics == .dxmt)
        #expect(try raw()["DXVK"] as? Int == 0)
    }

    @Test func placeholderProgramHasNoName() {
        let settings = BottleSettings(graphics: .d3dMetal, metalHUD: false, msync: true, programPath: "/nothing.exe")
        #expect(settings.programName == nil)
    }
}

struct ShortcutTests {
    @Test func findsStartMenuShortcutsButNotUninstallers() throws {
        let fixture = try BottleFixture(name: "Office")
        let menu = "Microsoft/Windows/Start Menu/Programs"
        try fixture.write("", to: "ProgramData/\(menu)/Notepad++/Notepad++.lnk")
        try fixture.write("", to: "ProgramData/\(menu)/Notepad++/Uninstall Notepad++.lnk")
        try fixture.write("", to: "users/player/AppData/Roaming/\(menu)/Tool.lnk")
        try fixture.write("", to: "users/player/AppData/Roaming/\(menu)/readme.txt")
        #expect(Shortcuts.find(in: fixture.bottle).map(\.name) == ["Notepad++", "Tool"])
    }
}

struct WineTests {
    @Test func detectsRunningBottleFromItsWineserver() throws {
        let fixture = try BottleFixture()
        let other = Bottle(url: URL(fileURLWithPath: "/Users/x/Applications/Sikarugir/Other.app"))
        let commands = [
            fixture.bottle.contents.path + "/SharedSupport/wine/lib/wine/../../bin/wineserver",
            #"C:\Program Files (x86)\Steam\steam.exe"#,
        ]
        #expect(Wine.isRunning(fixture.bottle, among: commands))
        #expect(!Wine.isRunning(other, among: commands))
    }

    @Test func mapsMacFilesToZDrive() {
        let file = URL(fileURLWithPath: "/Users/player/Downloads/Setup Tool.exe")
        #expect(Wine.windowsPath(for: file) == #"Z:\Users\player\Downloads\Setup Tool.exe"#)
        #expect(Wine.windowsPath(for: file.deletingLastPathComponent()) == #"Z:\Users\player\Downloads"#)
    }

    @Test func escapesPercentSignsInRunScripts() throws {
        let fixture = try BottleFixture()
        // The fixture has no launcher, so starting fails after the script is written.
        #expect(throws: (any Error).self) {
            try Wine.run(URL(fileURLWithPath: "/Users/player/Downloads/setup%20v2.exe"), in: fixture.bottle)
        }
        let script = try String(contentsOf: fixture.bottle.driveC.appending(path: "cellar/run-program.bat"), encoding: .utf8)
        #expect(script.contains(#""Z:\Users\player\Downloads\setup%%20v2.exe""#))
    }

    @Test func bottleEqualityIgnoresTrailingSlash() {
        let plain = Bottle(url: URL(fileURLWithPath: "/x/Steam.app"))
        let listed = Bottle(url: URL(fileURLWithPath: "/x/Steam.app/", isDirectory: true))
        #expect(plain == listed)
    }
}

/// Builds a real bottle with the real Wine engine. Slow (about a minute), so it only runs
/// when CELLAR_E2E names a scratch folder to build in: `CELLAR_E2E=/tmp/x ./test.sh`.
struct EndToEndTests {
    static let folder = ProcessInfo.processInfo.environment["CELLAR_E2E"]

    @Test(.enabled(if: folder != nil))
    func createsBottleRunsProgramAndStops() async throws {
        let folder = URL(fileURLWithPath: Self.folder!)
        let name = "Cellar E2E \(UUID().uuidString.prefix(6))"
        if Wine.processCommands().contains(where: { $0.hasSuffix("/wineserver") }) {
            // Another bottle (say, Steam) is open: creation must refuse rather than hang.
            await #expect(throws: BottleFactory.Failure.otherBottleRunning) {
                try await BottleFactory.create(named: name, in: folder)
            }
            return
        }
        let bottle = try await BottleFactory.create(named: name, in: folder)
        #expect(bottle.name == name)
        #expect(!bottle.url.lastPathComponent.contains(" "))
        #expect(Bottle.discover(in: folder).contains(bottle))
        #expect(try BottleSettings.load(from: bottle.infoPlist).graphics == .dxmt)

        // A program run from a Mac path with spaces in it…
        let script = folder.appending(path: "hello world.bat")
        try "@echo cellar-ok> C:\\marker.txt\r\n".write(to: script, atomically: true, encoding: .utf8)
        try Wine.run(script, in: bottle)
        #expect(try await contents(of: bottle.driveC.appending(path: "marker.txt"))?.contains("cellar-ok") == true)
        #expect(Wine.isRunning(bottle, among: Wine.processCommands()))

        // …and a command with arguments, the way Play launches Steam games.
        try Wine.runScript(named: "e2e", #"echo with-args %PROCESSOR_ARCHITECTURE%> C:\marker2.txt"#, in: bottle)
        #expect(try await contents(of: bottle.driveC.appending(path: "marker2.txt"))?.contains("with-args") == true)

        try await Wine.stop(bottle)
        try await Task.sleep(for: .seconds(2))
        #expect(!Wine.isRunning(bottle, among: Wine.processCommands()))
    }

    /// Waits up to a minute for Wine to write a file (Windows creates it before filling it in).
    private func contents(of file: URL) async throws -> String? {
        for _ in 0..<60 {
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty { return text }
            try await Task.sleep(for: .seconds(1))
        }
        return nil
    }
}

struct BottleFactoryTests {
    @Test func rejectsBadOrDuplicateNamesBeforeDoingAnything() async throws {
        let fixture = try BottleFixture()
        await #expect(throws: BottleFactory.Failure.invalidName) {
            try await BottleFactory.create(named: "  ", in: fixture.root)
        }
        await #expect(throws: BottleFactory.Failure.invalidName) {
            try await BottleFactory.create(named: "a/b", in: fixture.root)
        }
        await #expect(throws: BottleFactory.Failure.alreadyExists("Steam")) {
            try await BottleFactory.create(named: "Steam", in: fixture.root)
        }
        await #expect(throws: BottleFactory.Failure.alreadyExists("steam")) {
            try await BottleFactory.create(named: "steam", in: fixture.root)
        }
    }

    @Test func folderNamesAvoidSpacesButBottlesKeepTheirName() throws {
        #expect(BottleFactory.folderName(for: "Epic Games!") == "EpicGames")
        #expect(BottleFactory.folderName(for: "My-Apps_2") == "My-Apps_2")
        #expect(BottleFactory.folderName(for: "日本") == "Bottle")

        let fixture = try BottleFixture(name: "EpicGames")
        let plist: [String: Any] = ["CellarName": "Epic Games"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: fixture.bottle.infoPlist)
        #expect(Bottle(url: fixture.bottle.url).name == "Epic Games")
    }
}

struct WineLogTests {
    @Test func loggingToggleWritesDebugModeAndWineDebug() throws {
        let fixture = try BottleFixture()
        let plist = fixture.bottle.infoPlist
        let start: [String: Any] = ["Debug Mode": 0, "WINEDEBUG": "-all", "DXMT": 1, "CFBundleName": "Steam"]
        try PropertyListSerialization.data(fromPropertyList: start, format: .xml, options: 0).write(to: plist)
        func raw() throws -> [String: Any] {
            try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        }

        var settings = try BottleSettings.load(from: plist)
        #expect(!settings.logWineOutput)
        settings.logWineOutput = true
        try settings.save(to: plist)
        #expect(try raw()["Debug Mode"] as? Int == 1)
        #expect(try raw()["WINEDEBUG"] as? String == "err+all,fixme-all")
        #expect(try BottleSettings.load(from: plist).logWineOutput)

        settings.logWineOutput = false
        try settings.save(to: plist)
        #expect(try raw()["Debug Mode"] as? Int == 0)
        #expect(try raw()["WINEDEBUG"] as? String == "-all")
        #expect(try raw()["CFBundleName"] as? String == "Steam")

        // A WINEDEBUG set by hand survives saves that don't flip the switch.
        try BottleSettings.edit(plist) { $0["WINEDEBUG"] = "+relay" }
        settings.metalHUD = true
        try settings.save(to: plist)
        #expect(try raw()["WINEDEBUG"] as? String == "+relay")
    }

    @Test func summarisesTheLinesThatExplainACrash() {
        let report = WineLogReport(text: #"""
        msync: up and running.
        002c:err:virtual:try_map_free_area mmap() error Cannot allocate memory, range 0x7ffffffb0000-0x7ffffffe9000, unix_prot 0x3.
        0024:err:module:import_dll Library xinput1_4.dll (which is needed by L"C:\\Games\\Game.exe") not found
        0024:err:module:import_dll Library xinput1_4.dll (which is needed by L"C:\\Games\\Other.dll") not found
        0024:err:module:loader_init Importing dlls for L"C:\\Games\\Game.exe" failed, status c0000135
        0110:err:d3d11:d3d11_device_CreateTexture2D Failed to create texture
        wine: Call from 00006FFFFFF8A1B4 to unimplemented function api-ms-win-core-foo-l1-1-0.dll.Bar, aborting
        wine: Unhandled page fault on read access to 0000000000000000 at address 0000000140012345 (thread 0124), starting debugger...
        00f0:err:rundll32:wWinMain Unable to find the entry point
        info:  DXMT: using a deferred context
        """#)
        #expect(report.summary == [
            "Missing DLL: xinput1_4.dll",
            "Unimplemented function: api-ms-win-core-foo-l1-1-0.dll.Bar",
            "Crash: page fault on read access to 0000000000000000 at address 0000000140012345",
            "Graphics errors: 1 (d3d, vkd3d or DXMT)",
        ])
        #expect(report.lines.map(\.kind) == [.noise, .noise, .module, .module, .module, .graphics, .unimplemented, .pageFault, .plain, .plain])
    }

    @Test func readsAroundTheHoleALaterLauncherRunLeaves() throws {
        let fixture = try BottleFixture()
        let log = WineLog.live(for: fixture.bottle)
        try FileManager.default.createDirectory(at: WineLog.folder(for: fixture.bottle), withIntermediateDirectories: true)
        try (Data("second run\n".utf8) + Data(count: 2000) + Data("first run, later\n".utf8)).write(to: log)
        #expect(WineLog.read(log) == "second run\nfirst run, later\n")
        #expect(WineLog.newest(for: fixture.bottle) == log)
    }

    @Test func capsTheLiveLogAndKeepsAFewCopies() throws {
        let fixture = try BottleFixture()
        let bottle = fixture.bottle
        let log = WineLog.live(for: bottle)
        try FileManager.default.createDirectory(at: WineLog.folder(for: bottle), withIntermediateDirectories: true)

        try Data(repeating: UInt8(ascii: "x"), count: 5 << 20).write(to: log)
        WineLog.enforceLimit(bottle)
        let copies = WineLog.copies(for: bottle)
        #expect(copies.count == 1)
        #expect(WineLog.stored(log) == 0)
        #expect(try Data(contentsOf: copies[0]).count == WineLog.keptTail)
        #expect(WineLog.newest(for: bottle) == copies[0])

        for second in 1...4 {
            try Data("run \(second)\n".utf8).write(to: log)
            WineLog.preserve(bottle, now: Date(timeIntervalSince1970: TimeInterval(second * 60)))
        }
        #expect(WineLog.copies(for: bottle).count == WineLog.keptCopies)

        WineLog.clear(bottle)
        #expect(WineLog.copies(for: bottle).isEmpty)
        #expect(WineLog.newest(for: bottle) == nil)
    }
}
