# Notch

A Dynamic Island for the MacBook notch that costs **0% CPU** while idle.

Most notch apps poll media state on a timer and animate on the main thread all
day, which is why they warm your lap. This one is event-driven end to end:
nothing ticks unless the notch is open, and the only thing that animates while
it's closed (the equalizer) runs in Core Animation, out of process.

## What it does

**Collapsed pill** (hover or `⌃⌥N` to open)
- Album art + equalizer in the album's colour while Spotify plays; hidden when paused
- Live timer / stopwatch digits when one is running
- Pops for charger plug/unplug, low battery (20 / 10 / 5%), Bluetooth connect/disconnect
- A "Good morning" island at login: time-of-day glyph, clock, battery count-up

**Now Playing** — artwork (click → opens Spotify), title/artist, scrubbable
progress bar, prev / play-pause / next, shuffle, repeat. Uses Spotify's
public scripting API and its playback-change broadcast — no private
frameworks, no polling.

**Shelf** — drag files onto the notch to park them. Accepts real files, macOS
screenshot thumbnails, and images dragged from apps. QuickLook thumbnails,
multi-select, drag out as a bundle, Quick Look preview, AirDrop zone.

**Clock** — stopwatch, and a timer you can type into (`25`, `12:30`, `1h20m`,
`90s`). Rings and opens the notch when done.

**Works on every display** — real notch on the MacBook, a virtual pill on
external monitors, same shelf/music/clock underneath.

## Install

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).
No Xcode needed.

```bash
git clone <this repo> notch && cd notch
./scripts/install.sh
```

That builds an optimised `Notch.app`, copies it to `/Applications`, launches it,
and registers it as a login item (toggle in the menu bar icon). No Dock icon.

First time you press play/pause macOS will ask to let Notch control Spotify —
allow it.

## Develop

```bash
./scripts/run.sh          # debug build + relaunch
./scripts/debug.sh expand # drive the UI from a script (debug builds only)
```

Feel tunables (springs, delays, sizes) live in `Motion` in
`Sources/Notch/App/NotchState.swift`.

### Signing

Builds are ad-hoc signed by default. If you create a self-signed *Code Signing*
certificate named `Notch Dev` in Keychain Access, the build script uses it, so
macOS permissions survive rebuilds.

## Layout

```
Sources/Notch
├── App/        entry point, per-panel state, login item, hotkey
├── Panel/      NSPanel over the notch, geometry, hover + drag-and-drop
├── Views/      SwiftUI: notch shape, Now Playing, shelf, clock, greeting, pops
└── Features/   Spotify, shelf store, clock, power / Bluetooth monitors
```

## License

MIT
