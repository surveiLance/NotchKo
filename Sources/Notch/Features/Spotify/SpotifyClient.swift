import AppKit
import Combine

struct SpotifyTrack: Equatable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

/// Spotify integration with zero polling.
///
/// Spotify broadcasts `com.spotify.client.PlaybackStateChanged` on every
/// play/pause/skip/seek. We read track metadata straight from that
/// notification and only touch AppleScript for two things: the artwork URL
/// (once per track) and transport commands (on click). Playback position is
/// derived from the last notification + wall clock, so nothing ticks while
/// the notch is closed.
@MainActor
final class SpotifyClient: ObservableObject {
    static let bundleID = "com.spotify.client"

    @Published private(set) var track: SpotifyTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    /// Dominant colour of the current artwork; drives the equaliser, progress bar, etc.
    @Published private(set) var accent: NSColor = .systemGreen
    @Published private(set) var shuffling = false
    @Published private(set) var repeating = false
    /// Spotify's own volume, 0–100 (separate from the system volume).
    @Published private(set) var volume = 100
    private var volumeWork: DispatchWorkItem?

    /// Position at `positionAnchor`; extrapolate while playing.
    private var positionBase: TimeInterval = 0
    private var positionAnchor = Date()

    private var artworkCache: [String: (NSImage, NSColor)] = [:]
    private var artworkTask: Task<Void, Never>?
    private let scriptQueue = DispatchQueue(label: "notch.spotify.applescript")

    init() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        if Self.isRunning { refreshFromAppleScript() }
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var position: TimeInterval {
        guard let track else { return 0 }
        let p = isPlaying ? positionBase + Date().timeIntervalSince(positionAnchor) : positionBase
        return min(max(p, 0), track.duration)
    }

    // MARK: - Events

    @objc private func playbackChanged(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let state = info["Player State"] as? String ?? "Stopped"
        if state == "Stopped" {
            clear(); return
        }
        let id = info["Track ID"] as? String ?? ""
        let durationMS = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        let newTrack = SpotifyTrack(
            id: id,
            name: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: durationMS / 1000
        )
        positionBase = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
        positionAnchor = Date()
        isPlaying = state == "Playing"
        if newTrack != track {
            track = newTrack
            loadArtwork(for: newTrack)
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app?.bundleIdentifier == Self.bundleID { clear() }
    }

    private func clear() {
        track = nil; isPlaying = false; artwork = nil
        artworkTask?.cancel()
    }

    // MARK: - Artwork

    private func loadArtwork(for track: SpotifyTrack) {
        if let (image, color) = artworkCache[track.id] { artwork = image; accent = color; return }
        artwork = nil
        accent = .systemGreen
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let self else { return }
            guard let urlString = await self.runScript("tell application \"Spotify\" to get artwork url of current track"),
                  let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data),
                  !Task.isCancelled, self.track?.id == track.id
            else { return }
            let color = image.accentColor() ?? .systemGreen
            self.artworkCache[track.id] = (image, color)
            if self.artworkCache.count > 20 { self.artworkCache.removeAll() }
            self.artwork = image
            self.accent = color
        }
    }

    // MARK: - Transport

    func playPause() { send("playpause") }
    func next()      { send("next track") }
    func previous()  { send("previous track") }

    /// Jump within the current track. Local state updates immediately;
    /// Spotify confirms with a PlaybackStateChanged shortly after.
    func seek(to seconds: TimeInterval) {
        guard let track else { return }
        let t = min(max(0, seconds), track.duration)
        positionBase = t
        positionAnchor = Date()
        send("set player position to \(t)")
    }

    func toggleShuffle() {
        shuffling.toggle()
        send("set shuffling to \(shuffling)")
    }

    func toggleRepeat() {
        repeating.toggle()
        send("set repeating to \(repeating)")
    }

    /// Shuffle/repeat/volume aren't in the notification; read them when the player UI appears.
    func refreshModes() {
        guard Self.isRunning else { return }
        Task { [weak self] in
            guard let self,
                  let out = await self.runScript("tell application \"Spotify\" to return (shuffling as string) & \",\" & (repeating as string) & \",\" & (sound volume as string)")
            else { return }
            let parts = out.split(separator: ",")
            if parts.count == 3 {
                self.shuffling = parts[0] == "true"
                self.repeating = parts[1] == "true"
                if let v = Int(parts[2]) { self.volume = v }
            }
        }
    }

    /// Slider updates come in bursts while dragging; the UI reflects each
    /// one immediately and Spotify gets told at most every 60 ms.
    func setVolume(_ v: Int) {
        let clamped = min(max(v, 0), 100)
        volume = clamped
        volumeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.send("set sound volume to \(clamped)") }
        volumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    /// Bring the Spotify app forward.
    func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(_ command: String) {
        guard Self.isRunning else { return }
        Task { _ = await runScript("tell application \"Spotify\" to \(command)") }
    }

    /// Initial sync on launch, when there's no notification to read yet.
    private func refreshFromAppleScript() {
        Task { [weak self] in
            guard let self else { return }
            let script = """
            tell application "Spotify"
                if player state is stopped then return ""
                set t to current track
                return (id of t) & "\n" & (name of t) & "\n" & (artist of t) & "\n" & (album of t) & "\n" & (duration of t) & "\n" & (player position) & "\n" & (player state as string)
            end tell
            """
            guard let out = await self.runScript(script), !out.isEmpty else { return }
            let f = out.components(separatedBy: "\n")
            guard f.count >= 7 else { return }
            let t = SpotifyTrack(id: f[0], name: f[1], artist: f[2], album: f[3],
                                 duration: (Double(f[4]) ?? 0) / 1000)
            self.positionBase = Double(f[5]) ?? 0
            self.positionAnchor = Date()
            self.isPlaying = f[6] == "playing"
            self.track = t
            self.loadArtwork(for: t)
        }
    }

    private func runScript(_ source: String) async -> String? {
        await withCheckedContinuation { cont in
            scriptQueue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error { NSLog("AppleScript: \(error)") }
                cont.resume(returning: result?.stringValue)
            }
        }
    }
}
