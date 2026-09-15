import IOKit.ps

/// Charger plug/unplug and low-battery thresholds. IOKit calls us on change.
@MainActor
final class PowerMonitor {
    var onCharging: ((Bool, Int) -> Void)?
    var onLowBattery: ((Int) -> Void)?

    private var lastCharging: Bool?
    private var warnedAt: Int?
    private var source: CFRunLoopSource?

    init() {
        lastCharging = Battery.read()?.charging
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in me.changed() }
        }, selfPtr)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func changed() {
        guard let s = Battery.read() else { return }
        if s.charging != lastCharging {
            lastCharging = s.charging
            onCharging?(s.charging, s.percent)
        }
        if s.charging {
            warnedAt = nil
        } else {
            for threshold in [20, 10, 5] where s.percent <= threshold && (warnedAt ?? 100) > threshold {
                warnedAt = threshold
                onLowBattery?(s.percent)
                break
            }
        }
    }
}
