import SwiftUI

struct DevicesView: View {
    @ObservedObject var devices: DevicesStore

    var body: some View {
        Group {
            if devices.devices.isEmpty {
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if devices.loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 22))
                        Text("Nothing connected").font(.system(size: 11))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(devices.devices) { DeviceRow(device: $0) }
                    }
                }
            }
        }
        .onAppear { devices.refresh() }
    }
}

private struct DeviceRow: View {
    let device: Device
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(device.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            HStack(spacing: 6) {
                ForEach(device.batteries, id: \.label) { b in
                    BatteryBadge(label: b.label, percent: b.percent)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hovering ? 0.07 : 0)))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name), \(device.detail)" + device.batteries.map { ", \($0.label) \($0.percent) percent" }.joined())
    }
}

private struct BatteryBadge: View {
    let label: String
    let percent: Int

    private var tint: Color {
        percent <= 20 ? .red : (percent <= 40 ? .orange : .green)
    }

    var body: some View {
        HStack(spacing: 3) {
            if !label.isEmpty {
                Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.35), lineWidth: 1).frame(width: 18, height: 9)
                RoundedRectangle(cornerRadius: 1).fill(tint)
                    .frame(width: max(2, 16 * CGFloat(percent) / 100), height: 7)
                    .offset(x: 1)
            }
            Text("\(percent)%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
