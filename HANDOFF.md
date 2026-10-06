# NotchKo — context for picking this up

Written for another agent (or future me) taking over mid-stream. The README is
for users; this is the stuff you'd otherwise have to rediscover.

Repo: https://github.com/surveiLance/NotchKo · local: `/Users/lance/Work/notch`

---

## What it is

A macOS background agent (`LSUIElement`, no Dock icon, no window) that draws a
panel over the MacBook notch. Hover it or press ⌃⌥N and it opens into a tabbed
panel; move away and it tucks back.

Swift + SwiftUI inside an AppKit `NSPanel`. **Swift Package Manager, no Xcode
project** — `scripts/build.sh` compiles and hand-rolls the `.app` bundle.

```bash
./scripts/run.sh              # debug build + relaunch
./scripts/install.sh          # optimised build → /Applications + relaunch
./scripts/debug.sh <action>   # drive the UI without a mouse (DEBUG builds only)
./scripts/test-sizes.sh       # panel-size sweep, see Testing below
```

Signing: if a self-signed *Code Signing* cert named `Notch Dev` exists in the
keychain, the build uses it, which keeps TCC grants (camera etc.) across
rebuilds. Otherwise ad-hoc, and permissions reset on every build.

---

## The one rule that shapes everything

**0% CPU when idle.** Nothing polls. Every data source either pushes to us or is
read on demand:

| Source | Mechanism |
|---|---|
| Spotify | `DistributedNotificationCenter` → `com.spotify.client.PlaybackStateChanged` |
| Charger / battery | `IOPSNotificationCreateRunLoopSource` |
| Bluetooth | `IOBluetoothDevice.register(forConnectNotifications:)` |
| Displays / Spaces | `NSApplication.didChangeScreenParametersNotification`, `NSWorkspace.activeSpaceDidChangeNotification` |
| Devices / agents | Scanned **only when their tab opens**, cached by file mtime |
| Camera | Session runs only while the Mirror tab is visible |

Elapsed/remaining times are derived from wall-clock anchors, never from a
running timer. `TimelineView` is used with `paused:` or a 3600s interval when
nothing is moving.

Two honest exceptions, both documented in the README: the collapsed equalizer
costs ~9% of **WindowServer** (not the app) while music plays, and the Mirror
tab uses the camera while open.

**No private frameworks.** Spotify integration is its public scripting
interface plus its broadcast notification. If you're tempted by `MediaRemote`,
don't — surviving macOS updates is a selling point here.

---

## Layout

```
Sources/Notch/
├── App/
│   ├── NotchApp.swift        @main
│   ├── AppDelegate.swift     panels per display, menu bar, system notices, DEBUG hooks
│   ├── NotchState.swift      per-panel UI state + Tab enum + Motion (all tunables)
│   ├── Services.swift        the one-per-app stores, shared by every panel
│   ├── HotKey.swift          ⌃⌥N via Carbon
│   └── LoginItem.swift       SMAppService
├── Panel/
│   ├── NotchPanel.swift      the NSPanel: sizing, window animation, Quick Look
│   ├── NotchGeometry.swift   notch detection per screen, CGDirectDisplayID helpers
│   └── HoverHostingView.swift  tracking area + AppKit drag-and-drop
├── Views/                    one file per tab, plus NotchShape / NoticeView
└── Features/                 the stores behind each tab
```

**`Services`** holds everything shared (Spotify, shelf, clock, devices, camera,
agents, settings). **`NotchState`** is per-panel — there's one panel *per
display*, each with its own state but pointing at the same services.

**`Motion`** (bottom of `NotchState.swift`) is where every spring, delay and
size lives. Change feel there, not in views. Its animations are computed
properties that scale with the user's speed setting and collapse to short fades
under `accessibilityDisplayShouldReduceMotion`.

---

## Traps that cost real time

These are all things that already bit us. Read before debugging something weird.

**`@Published` fires on `willSet`.** A Combine sink reading another property of
the same object sees the *old* value. `NotchPanel` works around this by hopping
`DispatchQueue.main.async` before reading `state.expandedSize`. If a resize is
one tab behind, this is why.

**Don't animate the same geometry twice.** The window animates to its new size
*and* SwiftUI must not animate its own frame to the same target — two
independent animations make the content trail the window, which reads as lag.
When open, the panel content fills the window (`maxWidth/maxHeight: .infinity`)
and the window animation is the only thing moving layout. Fixed in `16cba13`.

**`NSHostingView` is flipped.** y = 0 is the *top*. A tracking rect placed with
bottom-left maths lands in the wrong half; that's why hovering below the notch
used to reopen it (`419d244`).

**The window stays oversized after a collapse** (~0.5s) so the shrink can
animate. The hover tracking rect is narrowed to the pill immediately, otherwise
anything under that invisible area reopens the notch.

**Distributed notifications to a background agent get suspended** once the app
has been activated — `./scripts/debug.sh` silently stops working mid-session.
The DEBUG observer is registered selector-based with
`suspensionBehavior: .deliverImmediately` to prevent this. If debug commands
start being ignored, check that registration first.

**Swift `String` splitting is pathologically slow on large files.** ~2s per 45MB
transcript. `AgentsStore` memory-maps and splits on newline *bytes*, converting
only matching lines to JSON. Don't "simplify" it back to `String(contentsOf:)`.

**Panel sizes must clear the tab strips.** `NotchState.widthForTabs` computes
the minimum; `fit()` clamps to it and to the screen. Add a tab and this adjusts
automatically.

---

## Where the data comes from

### Spotify
Scripting only. Track metadata arrives in the notification's `userInfo`
(`Track ID`, `Name`, `Artist`, `Duration`, `Playback Position`, `Player State`).
AppleScript is used only for artwork URL, transport, volume and
shuffle/repeat/position reads. Accent colour is extracted in
`ArtworkColor.swift` — saturation²×brightness weighted, then clamped so it
reads on black.

### AI agents (`AgentsStore`)
Both CLIs write JSONL locally. Nothing leaves the machine.

- **Claude Code** — `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`.
  Assistant lines carry `message.usage` (`input_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`) and
  `message.model`. Cache reads are **excluded** from totals — they'd dwarf
  everything. `cwd` isn't on every line, so the first 50 are checked.
- **Codex** — `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. `token_count`
  events carry `info.total_token_usage` (a running total, so take the latest,
  don't sum) and `rate_limits.primary/.secondary` with `used_percent` and
  `resets_at`.
- **Claude plan usage** is *not* in `~/.claude`. It's in the desktop app:
  `~/Library/Application Support/Claude/plan-usage-history.json`, `samples[]`,
  latest `.u` → `{"fh": five-hour %, "sd": seven-day %}`. Took a while to find.
- **Deep link** — `claude://code/continue?session=local_<uuid>`, where the uuid
  is the transcript filename. Route and its validator
  (`/^local_[A-Za-z0-9-]{1,64}$/`) were read out of
  `Claude.app/Contents/Resources/app.asar`. **Built but never clicked
  end-to-end — verify it lands on the right session.** Codex has no documented
  per-session route, so its rows just bring ChatGPT forward.

A session is "live" if its transcript was touched in the last 120s.

### Shelf / scan / tools
Drops are handled in **AppKit**, not SwiftUI, because the macOS screenshot
thumbnail is a *file promise* — the PNG doesn't exist until you release it, and
SwiftUI's `.onDrop` can't take it. A promise drag also advertises a temp file
URL that vanishes; ignore it when promises are present.

Vision is used for OCR (`VNRecognizeTextRequest`) and subject cut-out
(`VNGenerateForegroundInstanceMaskRequest`, macOS 14+). Always load images via
`CGImageSourceCreateThumbnailAtIndex` with
`kCGImageSourceCreateThumbnailWithTransform` — phone photos carry an EXIF
rotation flag and come out sideways otherwise.

---

## Settings (UserDefaults, `com.lance.notch`)

| Key | Meaning |
|---|---|
| `tabs.enabled` | array of tab raw values; Overview is always on |
| `tabs.hasChosen` | false → the picker opens on launch instead of the greeting |
| `tabs.sizeMode` | `auto` (each tab fits its content) or `uniform` (all tabs = largest enabled) |
| `motion.speed` | `fast` / `normal` / `relaxed`, scales every spring and delay |
| `appearance.artworkColour` | album colour wash + accent on/off |
| `shelf.paths`, `prompter.*`, `mirror.*` | per-feature state |
| `tabs.sizes` | **dead** — left over from the removed per-tab S/M/L. Safe to delete. |

---

## Testing

`scripts/test-sizes.sh` sweeps every tab × both size modes × 1/3/5/7/8 enabled
tabs and checks the window is sane. Last run: **48/48**.

It needs a `winid` helper that prints the panel's window id and size, and a
`parkmouse` helper, both expected at `.build/`. They're throwaway — recreate
with:

```swift
// winid.swift — swiftc -O winid.swift -o .build/winid
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Notch" {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print(w[kCGWindowNumber as String]!, "\(b["Width"]!)x\(b["Height"]!)")
}
```

```swift
// parkmouse.swift — swiftc -O parkmouse.swift -o .build/parkmouse
import CoreGraphics
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: CGPoint(x: 120, y: 820), mouseButton: .left)?.post(tap: .cghidEventTap)
```

**Automation gotchas.** The panel closes whenever the pointer isn't over it, so
park the mouse and re-send `expand` before every sample. Wait ~8s after launch —
the login greeting holds the panel for 3.6s and will corrupt the first reading.
Screenshots of the panel alone: `screencapture -o -x -l<windowID>`, which gives
a transparent-background capture with no desktop content behind it.

---

## Conventions

- Commits: plain prose explaining *why*, no bullet lists of files, ending with
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Comments explain the non-obvious (why a workaround exists), never restate the
  code.
- Don't invent data. When Claude Code's `<total_tokens>` reminder looked like a
  usage budget, it turned out to move 15,000,000 → 14,998,308 across a session
  that spent 22.4M tokens — so no dial was shipped rather than a meaningless
  one. Hold that line.
- Measure before claiming a perf or battery number. `top -l`, Activity Monitor's
  Energy tab, and comparing WindowServer with the app running vs quit.

---

## Open / next

- **Verify the Claude deep link** actually opens the right session.
- README's Agents section predates the redesign — it doesn't mention the
  activity lines, the bigger panel, or Claude's plan dials.
- `docs/portfolio/13-agents.png` is from before the redesign too.
- Old screenshots with personal content (Gmail, Docs titles, Messages) are gone
  from `docs/` but **remain in git history** — needs `git filter-repo` + force
  push if that matters.
- Collapsed pill doesn't show live agent activity; would need a file watcher,
  which breaks the no-background-work rule unless it's opt-in.
- Codex per-session deep link, if a route ever turns up.
- Apple Music support (same shape as the Spotify client).
