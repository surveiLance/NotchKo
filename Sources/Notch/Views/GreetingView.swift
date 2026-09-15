import SwiftUI

/// The "wake up" island shown once at login. Taller than the pill so it can
/// carry a real composition: glowing time-of-day glyph + small-caps label
/// over the name on the left; the time over the date and battery on the
/// right. Elements enter staggered, bottom-up.
struct GreetingView: View {
    let notchWidth: CGFloat
    let wing: CGFloat
    @State private var battery = 0.0
    @State private var appeared = false

    private let status = Battery.read()
    private let now = Date()
    private var hour: Int { Calendar.current.component(.hour, from: now) }

    private var greeting: String {
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Still up"
        }
    }
    private var symbol: String {
        switch hour {
        case 5..<8:   return "sunrise.fill"
        case 8..<17:  return "sun.max.fill"
        case 17..<20: return "sunset.fill"
        default:      return "moon.stars.fill"
        }
    }
    private var tint: Color {
        switch hour {
        case 5..<8:   return Color(red: 1.0, green: 0.62, blue: 0.30)
        case 8..<17:  return Color(red: 1.0, green: 0.80, blue: 0.30)
        case 17..<20: return Color(red: 1.0, green: 0.45, blue: 0.35)
        default:      return Color(red: 0.62, green: 0.66, blue: 1.0)
        }
    }
    private var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    }

    var body: some View {
        ZStack {
            // Soft wash of the time-of-day colour bleeding in from the glyph.
            RadialGradient(colors: [tint.opacity(0.22), .clear],
                           center: UnitPoint(x: 0.09, y: 0.55), startRadius: 0, endRadius: 170)
                .opacity(appeared ? 1 : 0)

            HStack(spacing: 0) {
                left.frame(width: wing)
                Spacer().frame(width: notchWidth)
                right.frame(width: wing)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.12)) { appeared = true }
            withAnimation(.easeOut(duration: 1.0).delay(0.35)) { battery = Double(status?.percent ?? 0) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(greeting), \(firstName). Battery \(status?.percent ?? 0) percent.")
    }

    // MARK: Left — glyph + label + name

    private var left: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0)], center: .center, startRadius: 2, endRadius: 22))
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.8), radius: 6)
            }
            .enter(appeared, delay: 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(greeting.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .enter(appeared, delay: 0.06)
                Text(firstName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .enter(appeared, delay: 0.12)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
    }

    // MARK: Right — time over date · battery

    private var right: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 19, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .enter(appeared, delay: 0.1)
                HStack(spacing: 5) {
                    Text(now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    if let status {
                        Text("·")
                        HStack(spacing: 3) {
                            Image(systemName: status.charging ? "bolt.fill" : "battery.100percent")
                                .font(.system(size: 8, weight: .bold))
                            CountingPercent(value: battery)
                        }
                        .foregroundStyle(batteryColor(status))
                    }
                }
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .enter(appeared, delay: 0.16)
            }
        }
        .padding(.trailing, 20)
    }

    private func batteryColor(_ s: Battery.Status) -> Color {
        if s.charging { return .green }
        return s.percent <= 20 ? .red : .white.opacity(0.7)
    }
}

/// Text that genuinely counts: the number is animatable data, so
/// withAnimation interpolates it frame by frame instead of crossfading.
private struct CountingPercent: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text("\(Int(value.rounded()))%")
            .contentTransition(.identity)
    }
}

private extension View {
    /// Staggered entrance: rise 6pt and fade in, on its own delay.
    func enter(_ on: Bool, delay: Double) -> some View {
        self
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 6)
            .blur(radius: on ? 0 : 3)
            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(delay), value: on)
    }
}
