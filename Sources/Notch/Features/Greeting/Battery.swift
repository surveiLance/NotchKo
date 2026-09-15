import IOKit.ps

enum Battery {
    struct Status { let percent: Int; let charging: Bool }

    /// One-shot read; nothing is observed or polled.
    static func read() -> Status? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let capacity = info[kIOPSCurrentCapacityKey as String] as? Int else { continue }
            let charging = (info[kIOPSIsChargingKey as String] as? Bool) ?? false
            return Status(percent: capacity, charging: charging)
        }
        return nil
    }
}
