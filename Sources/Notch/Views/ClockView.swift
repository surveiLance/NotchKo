import SwiftUI

struct ClockView: View {
    @ObservedObject var clock: ClockStore
    @ObservedObject var state: NotchState
    @State private var editing = false
    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            stopwatchCard
            timerCard
        }
    }

    // MARK: Stopwatch

    private var stopwatchCard: some View {
        Card(title: "Stopwatch", symbol: "stopwatch") {
            LiveText(every: clock.stopwatchRunning ? 0.1 : 3600) {
                ClockStore.format(clock.stopwatchElapsed, tenths: true)
            }
            .accessibilityLabel("Stopwatch \(ClockStore.format(clock.stopwatchElapsed))")
        } controls: {
            RoundButton(symbol: clock.stopwatchRunning ? "pause.fill" : "play.fill",
                        tint: clock.stopwatchRunning ? .orange : .green,
                        label: clock.stopwatchRunning ? "Pause stopwatch" : "Start stopwatch") { clock.stopwatchToggle() }
            RoundButton(symbol: "arrow.counterclockwise", tint: .gray, label: "Reset stopwatch") { clock.stopwatchReset() }
                .disabled(!clock.stopwatchHasValue)
                .opacity(clock.stopwatchHasValue ? 1 : 0.35)
        }
    }

    // MARK: Timer

    private var timerCard: some View {
        Card(title: clock.timerFired ? "Time's up" : (editing ? "Type a time, then ⏎" : "Timer"), symbol: "timer",
             tint: clock.timerFired ? .red : (editing ? .orange : nil)) {
            if editing {
                TextField("12:30 · 90s · 1h20m", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(invalid ? .red : .white)
                    .focused($focused)
                    .onSubmit(commitEdit)
                    .onExitCommand(perform: cancelEdit)
                    .onChange(of: draft) { _, v in invalid = !v.isEmpty && ClockStore.parse(v) == nil }
                    .onChange(of: focused) { _, f in if !f && editing { commitEdit() } }
                    .accessibilityLabel("Timer length. Type minutes, m:ss, or 1h20m")
            } else {
                LiveText(every: clock.timerRunning ? 1 : 3600) {
                    ClockStore.format(clock.timerRemaining)
                }
                .foregroundStyle(clock.timerFired ? .red : .white)
                .contentShape(Rectangle())
                .onTapGesture { if !clock.timerRunning && !clock.timerFired { beginEdit() } }
                .help(clock.timerRunning ? "" : "Click to type a time")
                .accessibilityLabel("Timer \(ClockStore.format(clock.timerRemaining))")
                .accessibilityHint(clock.timerRunning ? "" : "Click to type a length")
                .accessibilityAddTraits(clock.timerRunning ? [] : .isButton)
            }
        } controls: {
            if clock.timerRunning || clock.timerFired {
                RoundButton(symbol: clock.timerFired ? "checkmark" : "pause.fill",
                            tint: clock.timerFired ? .red : .orange,
                            label: clock.timerFired ? "Dismiss timer" : "Pause timer") { clock.timerToggle() }
            } else {
                RoundButton(symbol: "play.fill", tint: .green, label: "Start timer") { clock.timerToggle() }
            }
            RoundButton(symbol: "arrow.counterclockwise", tint: .gray, label: "Reset timer") { clock.timerReset() }
                .disabled(!clock.timerHasValue)
                .opacity(clock.timerHasValue ? 1 : 0.35)
            if !clock.timerRunning && !clock.timerFired {
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    Chip("-1") { clock.timerAdjust(by: -60) }
                    Chip("+1") { clock.timerAdjust(by: 60) }
                    Chip("+5") { clock.timerAdjust(by: 300) }
                    Chip("25") { clock.timerSet(25 * 60) }
                }
            }
        }
        .onChange(of: state.keyboardWanted) { _, wanted in
            // Focus lost elsewhere (click outside, notch closed) → drop out of editing.
            if !wanted && editing { cancelEdit() }
        }
    }

    private func beginEdit() {
        draft = ClockStore.format(clock.timerDuration)
        invalid = false
        editing = true
        state.keyboardWanted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }

    private func commitEdit() {
        if let secs = ClockStore.parse(draft) { clock.timerSet(secs) }
        endEdit()
    }

    private func cancelEdit() { endEdit() }

    private func endEdit() {
        editing = false
        focused = false
        state.keyboardWanted = false
    }
}

// MARK: - Pieces

/// Re-renders its text on a fixed cadence. Only alive while on screen.
private struct LiveText: View {
    let every: TimeInterval
    let text: () -> String
    var body: some View {
        TimelineView(.periodic(from: .now, by: every)) { _ in
            Text(text())
                .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
        }
    }
}

private struct Card<Readout: View, Controls: View>: View {
    let title: String
    let symbol: String
    var tint: Color? = nil
    @ViewBuilder let readout: Readout
    @ViewBuilder let controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint ?? .white.opacity(0.5))
            readout
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 6) { controls }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder((tint ?? .white).opacity(tint == nil ? 0.08 : 0.6), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: tint)
    }
}

private struct RoundButton: View {
    let symbol: String
    let tint: Color
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(hovering ? 0.9 : 0.7)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

private struct Chip: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false
    init(_ text: String, action: @escaping () -> Void) { self.text = text; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(hovering ? 0.2 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(text == "25" ? "Set timer to 25 minutes" : "\(text) minute")
    }
}
