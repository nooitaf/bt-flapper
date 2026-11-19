# bt-flapper

A lightweight macOS menu bar utility that prevents your MacBook from hogging Bluetooth devices (like headphones) while the lid is closed.

## What it does

- **Lid closed:** remembers all currently connected Bluetooth devices and disconnects them (coordinating briefly with macOS sleep so disconnects complete before suspend).
- **Dark wake while closed:** does **not** reconnect while the lid is closed, and disconnects if macOS grabs a device again during a background wake.
- **Lid opened:** makes a single, non-forceful attempt to reconnect each remembered device (the same as clicking it once in the macOS Bluetooth menu).
- **Menu bar controls:** lives quietly in the top menu bar with a simple **Enabled** toggle and **Quit** — no Dock icon, no extra bloat.

## Requirements

- macOS 13 (Ventura) or newer
- Xcode Command Line Tools (`xcode-select --install`) to build from source

## Install

### Download a release

Grab the latest `bt-flapper-v*.zip` from [Releases](https://github.com/nooitaf/bt-flapper/releases), unzip it, and drag `bt-flapper.app` into `/Applications`.

> **Note:** Because `bt-flapper` is ad-hoc signed rather than notarized with a paid Apple Developer ID, on first launch you may need to right-click `bt-flapper.app` → **Open** (or allow it in **System Settings → Privacy & Security**).

### Build from source

```bash
# Build bt-flapper.app
make app

# Launch it
make run

# Or install to /Applications
make install
```

On first launch, `bt-flapper` will:

1. Prompt for **Bluetooth** permission right away so it works on the very first lid close.
2. Ask if you'd like to enable **Launch at Login** (which you can also toggle anytime from the menu bar).

## Development

```bash
# Run unit tests
make test

# Clean build artifacts
make clean
```

## How it works

Written in native Swift with zero third-party dependencies:

- **IOKit (`IOPMrootDomain`)** observes `AppleClamshellState` for lid close/open events and hooks `IORegisterForSystemPower` to ensure Bluetooth disconnects finish before sleep.
- **IOBluetooth** reads connected paired devices (`IOBluetoothDevice.pairedDevices()`), disconnects via `closeConnection()`, and attempts a single reconnect via `openConnection()`.
- **AppKit** provides the menu bar icon (`NSStatusItem`) with `LSUIElement = true`.

## License

[MIT](LICENSE)
