import SwiftUI

/// Charger / bluetooth / low-battery pops in the collapsed pill.
/// Icon on the left wing, bar or text on the right.
struct NoticeView: View {
    let notice: Notice
    let notchWidth: CGFloat
    let wing: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: wing)
            Spacer().frame(width: notchWidth)
            right.frame(width: wing)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var left: some View {
        switch notice {
        case .power(let charging, _):
            Image(systemName: charging ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(charging ? .green : .orange)
        case .lowBattery:
            Image(systemName: "battery.25percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
        case .bluetooth(_, let connected, let isAudio):
            Image(systemName: isAudio ? "headphones" : "keyboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(connected ? .blue : .white.opacity(0.6))
        case .greeting:
            EmptyView()
        }
    }

    @ViewBuilder private var right: some View {
        switch notice {
        case .power(let charging, let percent):
            Text(charging ? "Charging · \(percent)%" : "\(percent)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(charging ? .green : .white.opacity(0.9))
                .lineLimit(1).minimumScaleFactor(0.8)
        case .lowBattery(let percent):
            Text("\(percent)% left")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.red)
        case .bluetooth(let name, let connected, _):
            Text(connected ? name : "\(name) off")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).truncationMode(.tail)
        case .greeting:
            EmptyView()
        }
    }

    private var label: String {
        switch notice {
        case .power(let c, let p): return c ? "Charging, \(p) percent" : "Unplugged, \(p) percent"
        case .lowBattery(let p): return "Low battery, \(p) percent"
        case .bluetooth(let n, let c, _): return "\(n) \(c ? "connected" : "disconnected")"
        case .greeting: return ""
        }
    }
}
