# Cellar

A native macOS front end for [Sikarugir](https://github.com/Sikarugir-App/Sikarugir) Wine wrappers ("bottles"). It lists your bottles, shows installed Steam games with their artwork, runs Windows programs and installers, and edits each bottle's graphics settings. Think CrossOver's bottle window, without the price.

Cellar does not include Wine. It drives the wrappers Sikarugir builds, which bring their own Wine engine, DXMT, D3DMetal and DXVK.

## Requirements

- Apple Silicon Mac, macOS 14 or later, Rosetta 2
- [Sikarugir](https://github.com/Sikarugir-App/Sikarugir), installed from its GitHub releases or `brew install --cask Sikarugir-App/sikarugir/sikarugir`
- Bottles in `~/Applications/Sikarugir`

## Install

Download `Cellar.dmg` from [Releases](https://github.com/Kamiko-Weeb/Cellar/releases) and drag Cellar into Applications.

The app is not notarized, so macOS blocks the first launch. Either right-click Cellar, choose Open, then Open again, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Cellar.app
```

## What it does

- **Bottles sidebar** with a running indicator
- **Games grid** read from each bottle's Steam libraries, including libraries on other drive letters (an external SSD mapped to `D:`, for example). Clicking a poster runs `steam.exe -applaunch <id>`, so Steam launch options such as `-nobattleye` still apply.
- **Programs** from the bottle's Start Menu shortcuts
- **Run Program…** for any `.exe`, `.msi`, `.bat` or `.lnk`
- **Settings** per bottle: renderer (D3DMetal, DXMT, DXVK), Metal FPS overlay, MSync
- **New Bottle** builds a wrapper from Sikarugir's Template 1.0.27 and the `WS12WineSikarugir11.0_1` engine (Wine 11, the first engine Rockstar's launcher runs on)

## Build from source

Only the Command Line Tools are needed, not Xcode.

```bash
./test.sh                  # unit tests
./build-app.sh --install   # builds build/Cellar.app and copies it to /Applications
./make-dmg.sh              # builds build/Cellar.dmg for a release
```

Two Command Line Tools workarounds live in the code: `test.sh` points the compiler at the Swift Testing macro plugin, and the views use a `ViewState` alias because the macOS 27 SDK's `@State` macro plugin ships only with Xcode.

`Cellar --snapshot out.png` renders every bottle, the settings sheet and the new-bottle sheet to PNGs in light and dark mode without opening a window. Set `CELLAR_BOTTLES_DIR` to point it at a folder of test bottles.

## Sikarugir quirks Cellar works around

Found while getting GTA V running:

- The wrapper launcher speaks the old Wineskin command line and drops extra arguments, so Cellar runs anything that needs arguments through a small batch file in `drive_c/cellar`.
- The launcher never exits if the wrapper's path contains a space, so new bottles get space-free folder names; the display name is stored in `Info.plist` as `CellarName`.
- Creating a prefix waits until no `wineserver` runs anywhere on the Mac, so New Bottle asks you to stop running bottles first.
- The real Wine prefix is `Contents/SharedSupport/prefix`. Extra drive letters belong in its `dosdevices` folder, and should also be registered under `HKLM\Software\Wine\Drives`, or Wine drops them when the drive is unplugged.
- With `Symlinks In User Folder` on, the wrapper rebuilds the Windows user folders on every launch and removes the links if macOS denies folder access. Turning it off and keeping data inside the bottle avoids losing launcher logins.
- Bottles are opened through Launch Services, so they run under their own privacy permissions rather than Cellar's.

## Status

A personal project, tested on one machine. Expect rough edges.

## License

MIT. See [LICENSE](LICENSE).
