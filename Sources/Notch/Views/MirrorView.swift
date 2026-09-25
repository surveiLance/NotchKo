import AVFoundation
import AppKit
import SwiftUI

/// Quick self-check under the camera: live preview, source picker, mirror flip.
struct MirrorView: View {
    @ObservedObject var camera: CameraController

    var body: some View {
        Group {
            switch camera.authorization {
            case .authorized, .notDetermined:
                preview
            default:
                denied
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private var feed: some View {
        #if DEBUG
        if let demo = camera.demoImage {
            Image(nsImage: demo).resizable().aspectRatio(contentMode: .fill)
        } else {
            PreviewLayerView(session: camera.session)
        }
        #else
        PreviewLayerView(session: camera.session)
        #endif
    }

    private var preview: some View {
        ZStack(alignment: .bottom) {
            feed
                .background(Color.black)
                // Scrim so the controls stay legible over a bright room.
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 52)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .accessibilityLabel("Camera preview from \(camera.selectedName)")

            controls
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .opacity(camera.isRunning ? 1 : 0)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if camera.sources.count > 1 {
                Menu {
                    ForEach(camera.sources) { s in
                        Button(s.name) { camera.selectedID = s.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill").font(.system(size: 9, weight: .bold))
                        Text(camera.selectedName).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(Capsule().fill(.black.opacity(0.6)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Camera source")
            }

            Spacer(minLength: 0)

            Button { camera.mirrored.toggle() } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(camera.mirrored ? Color.accentColor : .white)
                    .frame(width: 26, height: 24)
                    .background(Capsule().fill(.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help(camera.mirrored ? "Showing a mirror image" : "Showing what others see")
            .accessibilityLabel("Mirror image")
            .accessibilityValue(camera.mirrored ? "On" : "Off")
        }
    }

    private var denied: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "video.slash.fill").font(.system(size: 22))
            Text("Camera access is off").font(.system(size: 11, weight: .semibold))
            Button("Open Privacy Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity)
    }
}

/// AVCaptureVideoPreviewLayer in a layer-backed NSView.
private struct PreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
