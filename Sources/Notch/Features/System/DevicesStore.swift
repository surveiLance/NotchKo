import AppKit
import IOKit.ps

struct Device: Identifiable, Equatable {
    enum Kind { case headphones, speaker, keyboard, mouse, gamepad, phone, charger, macBattery, display, other }
    let id: String
    let kind: Kind
    let name: String
    let detail: String
    /// Battery readouts, e.g. [("L", 99), ("R", 99), ("Case", 80)] or [("", 62)].
    let batteries: [(label: String, percent: Int)]

    static func == (a: Device, b: Device) -> Bool {
        a.id == b.id && a.detail == b.detail && a.batteries.map(\.percent) == b.batteries.map(\.percent)
    }

    var symbol: String {
        switch kind {
        case .headphones: return "airpods"
        case .speaker:    return "hifispeaker.fill"
        case .keyboard:   return "keyboard.fill"
        case .mouse:      return "computermouse.fill"
        case .gamepad:    return "gamecontroller.fill"
        case .phone:      return "iphone"
        case .charger:    return "powerplug.fill"
        case .macBattery: return "laptopcomputer"
        case .display:    return "display"
        case .other:      return "dot.radiowaves.left.and.right"
        }
    }
}

/// Everything plugged in or paired-and-connected. Refreshed on demand (when
/// the tab opens) and when Bluetooth/power change — never on a timer.
/// Bluetooth comes from `system_profiler`, the only public source that
/// includes AirPods per-bud battery.
@MainActor
final class DevicesStore: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var loading = false
    private var task: Task<Void, Never>?
    private var lastRefresh = Date.distantPast

    /// For the overview: reuse a recent snapshot instead of shelling out again.
    func refreshIfStale(_ maxAge: TimeInterval = 60) {
        if devices.isEmpty || Date().timeIntervalSince(lastRefresh) > maxAge { refresh() }
    }

    func refresh() {
        task?.cancel()
        lastRefresh = Date()
        loading = devices.isEmpty
        task = Task { [weak self] in
            let bluetooth = await Self.bluetoothDevices()
            guard !Task.isCancelled, let self else { return }
            var list = Self.powerDevices() + bluetooth + Self.displayDevices()
            list.sort { $0.kind.sortOrder < $1.kind.sortOrder }
            if list != self.devices { self.devices = list }
            self.loading = false
        }
    }

    // MARK: Power

    private static func powerDevices() -> [Device] {
        var out: [Device] = []
        if let b = Battery.read() {
            var detail = b.charging ? "Charging" : "On battery"
            if let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let srcs = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef],
               let first = srcs.first,
               let info = IOPSGetPowerSourceDescription(snap, first)?.takeUnretainedValue() as? [String: Any] {
                let toEmpty = info[kIOPSTimeToEmptyKey as String] as? Int ?? -1
                let toFull = info[kIOPSTimeToFullChargeKey as String] as? Int ?? -1
                if !b.charging, toEmpty > 0 { detail += " · \(toEmpty / 60)h \(toEmpty % 60)m left" }
                if b.charging, toFull > 0 { detail += " · full in \(toFull / 60)h \(toFull % 60)m" }
                if let health = info[kIOPSBatteryHealthKey as String] as? String { detail += " · \(health)" }
            }
            out.append(Device(id: "mac-battery", kind: .macBattery, name: "This Mac",
                              detail: detail, batteries: [("", b.percent)]))
        }
        if let a = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            let watts = a[kIOPSPowerAdapterWattsKey as String] as? Int
            let name = (a["Name"] as? String) ?? (a["Description"] as? String) ?? "Power adapter"
            let detail = watts.map { "\($0) W" } ?? "Connected"
            out.append(Device(id: "adapter", kind: .charger, name: name, detail: detail, batteries: []))
        }
        return out
    }

    // MARK: Displays

    private static func displayDevices() -> [Device] {
        NSScreen.screens.compactMap { s in
            guard s.safeAreaInsets.top == 0 else { return nil } // skip the built-in
            let px = s.frame.size.applying(CGAffineTransform(scaleX: s.backingScaleFactor, y: s.backingScaleFactor))
            return Device(id: "display-\(s.localizedName)", kind: .display, name: s.localizedName,
                          detail: "\(Int(px.width)) × \(Int(px.height))", batteries: [])
        }
    }

    // MARK: Bluetooth

    private static func bluetoothDevices() async -> [Device] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: parseBluetooth(runProfiler()))
            }
        }
    }

    private static func runProfiler() -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    private static func parseBluetooth(_ data: Data?) -> [Device] {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]],
              let connected = sections.first?["device_connected"] as? [[String: Any]]
        else { return [] }

        return connected.flatMap { entry -> [Device] in
            entry.compactMap { name, raw -> Device? in
                guard let v = raw as? [String: Any] else { return nil }
                let minor = (v["device_minorType"] as? String ?? "").lowercased()
                let kind: Device.Kind
                switch minor {
                case let m where m.contains("headphone") || m.contains("headset"): kind = .headphones
                case let m where m.contains("speaker") || m.contains("hi-fi"): kind = .speaker
                case let m where m.contains("keyboard"): kind = .keyboard
                case let m where m.contains("mouse") || m.contains("trackpad"): kind = .mouse
                case let m where m.contains("gamepad") || m.contains("controller"): kind = .gamepad
                case let m where m.contains("phone"): kind = .phone
                default: kind = .other
                }
                var batteries: [(String, Int)] = []
                func pct(_ key: String) -> Int? {
                    (v[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
                }
                if let l = pct("device_batteryLevelLeft") { batteries.append(("L", l)) }
                if let r = pct("device_batteryLevelRight") { batteries.append(("R", r)) }
                if let c = pct("device_batteryLevelCase") { batteries.append(("Case", c)) }
                if batteries.isEmpty, let m = pct("device_batteryLevelMain") ?? pct("device_batteryLevel") { batteries.append(("", m)) }
                let detail = (v["device_minorType"] as? String) ?? "Bluetooth"
                return Device(id: "bt-\(v["device_address"] as? String ?? name)", kind: kind,
                              name: name, detail: detail, batteries: batteries)
            }
        }
    }
}

private extension Device.Kind {
    var sortOrder: Int {
        switch self {
        case .headphones: return 0
        case .speaker: return 1
        case .keyboard, .mouse, .gamepad: return 2
        case .phone, .other: return 3
        case .charger: return 4
        case .macBattery: return 5
        case .display: return 6
        }
    }
}
