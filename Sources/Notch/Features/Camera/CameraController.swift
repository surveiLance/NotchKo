import AppKit
import AVFoundation
import Combine

/// Live camera for the mirror. The capture session only runs while the preview
/// is actually on screen — `start()` on appear, `stop()` on disappear — because
/// this is the one part of the app that genuinely costs power.
@MainActor
final class CameraController: ObservableObject {
    struct Source: Identifiable, Equatable {
        let id: String
        let name: String
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var isRunning = false
    @Published private(set) var authorization: AVAuthorizationStatus = .notDetermined
    @Published var selectedID: String? {
        didSet {
            guard selectedID != oldValue else { return }
            UserDefaults.standard.set(selectedID, forKey: "mirror.deviceID")
            if isRunning { reconfigure() }
        }
    }
    #if DEBUG
    /// Stand-in still shown instead of the live feed, for documentation shots.
    @Published var demoImage: NSImage?
    #endif

    /// Flip horizontally so it behaves like a mirror (on by default).
    @Published var mirrored: Bool {
        didSet {
            UserDefaults.standard.set(mirrored, forKey: "mirror.mirrored")
            applyMirroring()
        }
    }

    /// AVCaptureSession isn't Sendable, but ours is only mutated on `queue`
    /// (serial) and read by the preview layer, so hand it across in a box.
    private let box = SessionBox()
    var session: AVCaptureSession { box.session }
    private let queue = DispatchQueue(label: "notch.camera")

    init() {
        selectedID = UserDefaults.standard.string(forKey: "mirror.deviceID")
        mirrored = UserDefaults.standard.object(forKey: "mirror.mirrored") as? Bool ?? true
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        refreshSources()
        // Cameras come and go (iPhone Continuity, OBS, USB).
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshSources() } }
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshSources() } }
    }

    private func discover() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    private func refreshSources() {
        let devices = discover()
        sources = devices.map { Source(id: $0.uniqueID, name: $0.localizedName) }
        if selectedID == nil || !sources.contains(where: { $0.id == selectedID }) {
            selectedID = devices.first?.uniqueID
        }
    }

    var selectedName: String {
        sources.first { $0.id == selectedID }?.name ?? "No camera"
    }

    // MARK: Lifecycle

    func start() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.authorization = granted ? .authorized : .denied
                    if granted { self.configureAndRun() }
                }
            }
        default:
            break   // denied/restricted: the view shows how to fix it
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { [box] in
            if box.session.isRunning { box.session.stopRunning() }
        }
    }

    private func configureAndRun() {
        guard !isRunning else { return }
        isRunning = true
        swapInput(to: selectedID, preset: true, thenStart: true)
    }

    private func reconfigure() {
        swapInput(to: selectedID, preset: false, thenStart: false)
    }

    /// Device lookup happens on the session queue so only the id (a String)
    /// crosses the boundary.
    private func swapInput(to id: String?, preset: Bool, thenStart: Bool) {
        queue.async { [weak self, box] in
            let session = box.session
            let device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                mediaType: .video, position: .unspecified
            ).devices.first { $0.uniqueID == id }

            session.beginConfiguration()
            if preset { session.sessionPreset = .high }
            if let old = session.inputs.first { session.removeInput(old) }
            if let device, let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) {
                session.addInput(newInput)
            }
            session.commitConfiguration()
            if thenStart, !session.isRunning { session.startRunning() }
            Task { @MainActor in self?.applyMirroring() }
        }
    }

    private func applyMirroring() {
        let flip = mirrored
        queue.async { [box] in
            guard let conn = box.session.connections.first(where: { $0.isVideoMirroringSupported }) else { return }
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = flip
        }
    }
}


/// Carries the capture session between the main actor and the session queue.
/// Safe because every mutation happens on that one serial queue.
private final class SessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}
