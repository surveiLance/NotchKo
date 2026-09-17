import SwiftUI

// MARK: - Editor (the tab)

struct TeleprompterView: View {
    @ObservedObject var prompter: TeleprompterStore
    @ObservedObject var state: NotchState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompter.script)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .onChange(of: focused) { _, f in state.keyboardWanted = f }
                    .onChange(of: state.keyboardWanted) { _, w in if !w { focused = false } }
                    .padding(6)
                if !prompter.hasScript {
                    Text("Paste your script here…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 11).padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(focused ? 0.3 : 0.1), lineWidth: 1))
            .onTapGesture { focused = true }
            .accessibilityLabel("Teleprompter script")

            VStack(spacing: 6) {
                Button {
                    focused = false
                    state.startPrompter()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 18, weight: .bold))
                        Text("Start").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 54)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(prompter.hasScript ? Color.green.opacity(0.8) : .white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .disabled(!prompter.hasScript)
                .accessibilityLabel("Start teleprompter")

                HStack(spacing: 4) {
                    SmallButton(symbol: "doc.on.clipboard", label: "Paste script") {
                        if let s = NSPasteboard.general.string(forType: .string) { prompter.script = s }
                    }
                    SmallButton(symbol: "trash", label: "Clear script", tint: .red) { prompter.script = "" }
                }
                Text(wordCount)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var wordCount: String {
        let n = prompter.script.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let mins = Double(n) / 140   // ~140 wpm spoken
        return n == 0 ? "" : "\(n) words · ~\(max(1, Int(mins.rounded()))) min"
    }
}

// MARK: - Reading strip (pinned wide mode)

struct PrompterStripView: View {
    @ObservedObject var prompter: TeleprompterStore
    @ObservedObject var state: NotchState
    let notchSize: CGSize
    @State private var textHeight: CGFloat = 0

    private let readingLine: CGFloat = 0.38   // fraction of the text area height

    var body: some View {
        VStack(spacing: 4) {
            Spacer().frame(height: notchSize.height - 2)
            textArea
            controls.frame(height: 28)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var textArea: some View {
        GeometryReader { geo in
            let areaH = geo.size.height
            let lineY = areaH * readingLine
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !prompter.isRunning)) { ctx in
                let scrolled = CGFloat(prompter.scrolled(at: ctx.date))
                ZStack(alignment: .topLeading) {
                    // Reading guide, behind the text.
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.22))
                        .frame(height: prompter.fontSize * 1.5)
                        .offset(y: lineY - prompter.fontSize * 0.75)
                        .padding(.horizontal, -18)

                    Text(prompter.script)
                        .font(.system(size: prompter.fontSize, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(prompter.fontSize * 0.25)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)   // full height, never truncate
                        .background(GeometryReader { g in
                            Color.clear.preference(key: TextHeightKey.self, value: g.size.height)
                        })
                        .offset(y: lineY - scrolled)
                        .scaleEffect(x: prompter.mirrored ? -1 : 1)
                        .onChange(of: scrolled) { _, s in
                            if textHeight > 0, s > textHeight + lineY { prompter.reachedEnd() }
                        }

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                        .init(color: .black, location: 0.68), .init(color: .clear, location: 0.96)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .contentShape(Rectangle())
                .onTapGesture { prompter.togglePlay() }
            }
            .onPreferenceChange(TextHeightKey.self) { textHeight = $0 }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            SmallButton(symbol: "backward.end.fill", label: "Restart") { prompter.restart() }
            SmallButton(symbol: prompter.isRunning ? "pause.fill" : "play.fill",
                        label: prompter.isRunning ? "Pause" : "Play", tint: .green, prominent: true) { prompter.togglePlay() }
            SmallButton(symbol: "arrow.up", label: "Back a bit") { prompter.nudge(by: -prompter.fontSize * 3) }
            SmallButton(symbol: "arrow.down", label: "Forward a bit") { prompter.nudge(by: prompter.fontSize * 3) }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                SmallButton(symbol: "tortoise.fill", label: "Slower") { prompter.setSpeed(prompter.speed - 4) }
                Text(String(format: "%.0f", prompter.speed))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6)).frame(width: 22)
                SmallButton(symbol: "hare.fill", label: "Faster") { prompter.setSpeed(prompter.speed + 4) }
            }
            HStack(spacing: 4) {
                SmallButton(symbol: "textformat.size.smaller", label: "Smaller text") { prompter.fontSize = max(14, prompter.fontSize - 2) }
                SmallButton(symbol: "textformat.size.larger", label: "Larger text") { prompter.fontSize = min(40, prompter.fontSize + 2) }
            }
            SmallButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Mirror", active: prompter.mirrored) { prompter.mirrored.toggle() }

            Spacer(minLength: 0)

            SmallButton(symbol: "pencil", label: "Edit script") { state.stopPrompter(toEditor: true) }
            SmallButton(symbol: "xmark", label: "Close teleprompter", tint: .red) { state.stopPrompter(toEditor: false) }
        }
    }
}

private struct TextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SmallButton: View {
    let symbol: String
    let label: String
    var tint: Color = .white
    var prominent: Bool = false
    var active: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(prominent ? .white : (active ? Color.accentColor : tint.opacity(hovering ? 1 : 0.75)))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? tint.opacity(hovering ? 0.9 : 0.75) : .white.opacity(hovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
