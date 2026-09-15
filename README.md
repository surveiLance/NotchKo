# NotchKo

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

**Requirements:** macOS 14 Sonoma or newer. A notch is *not* required — on a
Mac without one (or on an external monitor) it draws a small virtual pill at
the top of the screen.

Pick whichever fits you:

### Option A — build it yourself (recommended, no security warnings)

You only need Apple's free Command Line Tools, not Xcode. In Terminal:

```bash
xcode-select --install
```

Wait for that to finish (it's ~1 GB), then:

```bash
git clone https://github.com/surveiLance/NotchKo.git && cd NotchKo && ./scripts/install.sh
```

About two minutes. This builds the app, puts `Notch.app` in `/Applications`,
launches it, and registers it to start at login. Because it was built on your
own Mac, macOS opens it without any warning.

### Option B — download the app

If someone sent you `Notch.app` (or you grabbed a zip from the Releases page):

1. Drag `Notch.app` into your **Applications** folder.
2. **Right-click → Open** the first time. macOS will say it "cannot check it for
   malicious software" — click **Open**. (It's not notarized by Apple; that
   costs $99/yr. You only have to do this once.)
   If the Open button isn't offered, go to **System Settings → Privacy &
   Security**, scroll down, and click **Open Anyway**.

It starts at login from then on.

### First run

- There's **no Dock icon and no window** — that's by design. Look for a small
  laptop icon in the menu bar (Launch at Login toggle, Quit) and hover the
  notch, or press **⌃⌥N**.
- The first time you press play/pause, macOS asks *"Notch wants to control
  Spotify"* → **Allow**. That's the only permission it needs.
- To remove it: Quit from the menu bar icon, delete `/Applications/Notch.app`.
  Parked shelf files (screenshots you dropped) live in
  `~/Library/Application Support/Notch/Shelf`.

## Using it

| Do this | Get this |
|---|---|
| Hover the notch, or ⌃⌥N | Panel opens with Music / Shelf / Clock tabs |
| Play something in Spotify | Album art + equalizer in the album's colour appear beside the notch |
| Drag a file, screenshot thumbnail, or image onto the notch | It's parked on the Shelf; drag it back out anywhere |
| Drop onto the blue AirDrop box | AirDrop picker opens straight away |
| Click a shelf file → eye icon | Quick Look preview |
| Click the timer digits | Type a length: `25`, `12:30`, `1h20m`, `90s` |
| Plug in / unplug, connect AirPods | A short pop in the pill |

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
