import AppKit
import SwiftUI

/// A floating, click-through panel at the top of the screen showing the orb and live captions.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private let assistant: Assistant
    private let meter: LevelMeter
    private var hideGeneration = 0
    private let size = NSSize(width: 460, height: 330)

    init(assistant: Assistant, meter: LevelMeter) {
        self.assistant = assistant
        self.meter = meter
    }

    func show() {
        hideGeneration += 1
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.hideGeneration == generation else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: HUDView().environmentObject(assistant).environmentObject(meter))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 6))
    }
}

struct HUDView: View {
    @EnvironmentObject var assistant: Assistant
    @EnvironmentObject var meter: LevelMeter

    var body: some View {
        VStack(spacing: 10) {
            OrbView(phase: assistant.phase, level: meter.level)
                .frame(width: 160, height: 160)
                .shadow(color: .black.opacity(0.35), radius: 12)

            let caption = assistant.hudCaption
            if !assistant.heard.isEmpty || caption != nil {
                VStack(spacing: 6) {
                    if !assistant.heard.isEmpty {
                        Text(assistant.heard)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    if let caption {
                        Text(caption)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 0.62, green: 0.92, blue: 1.0))
                            .lineLimit(5)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.62))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(red: 0.3, green: 0.85, blue: 1.0).opacity(0.35), lineWidth: 1)
                        )
                )
                .frame(maxWidth: 440)
                .transition(.opacity)
            }
        }
        .padding(.top, 6)
        .frame(width: 460, height: 330, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: assistant.heard)
    }
}
