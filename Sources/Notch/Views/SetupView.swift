import SwiftUI

/// The tab picker: shown once on first launch, and any time from the menu
/// bar. Keeping unused tabs off keeps the notch small.
struct SetupView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var tabs: TabSettings
    @ObservedObject var motion: MotionSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var tabSizes: TabSizeSettings
    /// First run gets a line of explanation; later visits don't need it.
    let firstRun: Bool

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(firstRun ? "What do you want in your notch?" : "Choose your tabs")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(firstRun
                         ? "Pick a few to start — you can change these any time from the menu bar."
                         : "Switch off what you don't use; the notch only shows what's on.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Button {
                    tabs.markChosen()
                    state.endSetup()
                } label: {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done choosing tabs")
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(NotchState.Tab.allCases) { tab in
                        TabChoice(tab: tab, on: tabs.isOn(tab), locked: tab.isRequired) {
                            tabs.toggle(tab)
                        }
                    }
                }
            }

            Divider().overlay(.white.opacity(0.1))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Animation speed")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    Text(motion.systemReducesMotion
                         ? "Reduce Motion is on in macOS — the notch fades instead"
                         : "How quickly the notch opens and closes")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(Motion.Speed.allCases) { s in
                        SpeedOption(title: s.title, on: motion.speed == s) { motion.speed = s }
                    }
                }
                .padding(2)
                .background(Capsule().fill(.white.opacity(0.07)))
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Panel size")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    Text(tabSizes.mode.blurb)
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(TabSizeSettings.Mode.allCases) { m in
                        SpeedOption(title: m.title, on: tabSizes.mode == m) { tabSizes.mode = m }
                    }
                }
                .padding(2)
                .background(Capsule().fill(.white.opacity(0.07)))
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Album colour")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    Text("Tint the music card and tab with the artwork's colour")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $appearance.artworkColour)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("Tint with album colour")
            }
        }
    }
}

private struct SpeedOption: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(on ? .white : .white.opacity(hovering ? 0.8 : 0.55))
                .padding(.horizontal, 11).frame(height: 22)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.8) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title) animation speed")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

private struct TabChoice: View {
    let tab: NotchState.Tab
    let on: Bool
    let locked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? .white : .white.opacity(0.45))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(on ? 0.16 : 0.06)))

                VStack(alignment: .leading, spacing: 0) {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(on ? .white : .white.opacity(0.6))
                    Text(locked ? "Always on" : tab.blurb)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Color.accentColor : .white.opacity(0.25))
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(hovering && !locked ? 0.12 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? Color.accentColor.opacity(0.5) : .white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .onHover { hovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityValue(on ? "Shown" : "Hidden")
        .accessibilityHint(locked ? "Always shown" : "Click to show or hide this tab")
    }
}
