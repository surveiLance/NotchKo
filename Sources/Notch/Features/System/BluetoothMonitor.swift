import IOBluetooth

/// Connect / disconnect pops for Bluetooth devices (AirPods, keyboards…).
@MainActor
final class BluetoothMonitor: NSObject {
    var onChange: ((_ name: String, _ connected: Bool, _ isAudio: Bool) -> Void)?

    override init() {
        super.init()
        IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        report(device, connected: true)
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
    }

    @objc private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        report(device, connected: false)
    }

    private func report(_ device: IOBluetoothDevice, connected: Bool) {
        let name = device.name ?? device.addressString ?? "Bluetooth device"
        let major = device.deviceClassMajor
        let isAudio = major == UInt32(kBluetoothDeviceClassMajorAudio)
        onChange?(name, connected, isAudio)
    }
}
