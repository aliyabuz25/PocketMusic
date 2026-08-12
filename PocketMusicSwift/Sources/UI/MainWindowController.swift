import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MainWindowController()

    private static let width: CGFloat = 1120
    private static let height: CGFloat = 740

    private init() {
        super.init(window: nil)
        buildWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildWindow() {
        let rect = centeredFrame()
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Pocket Music"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.055, alpha: 1)
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 900, height: 600)
        win.delegate = self

        let host = NSHostingView(rootView: PocketMusicAppView())
        host.frame = win.contentView?.bounds ?? rect
        host.autoresizingMask = [.width, .height]
        win.contentView = host

        window = win
    }

    private func centeredFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 80, width: Self.width, height: Self.height)
        }
        let vf = screen.visibleFrame
        return NSRect(
            x: vf.midX - Self.width / 2,
            y: vf.midY - Self.height / 2,
            width: Self.width,
            height: Self.height
        )
    }

    func present(from miniFrame: NSRect? = nil) {
        guard let window else { return }

        let target = centeredFrame()
        if let mini = miniFrame {
            window.setFrame(mini, display: true)
            window.alphaValue = 0.85
        } else {
            window.setFrame(target, display: true)
            window.alphaValue = 0
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        PocketMusicUIState.shared.windowVisible = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.48
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }

        Task { await PocketMusicUIState.shared.loadIfNeeded() }
    }

    func collapseToMiniPlayer() {
        guard let window else { return }

        let target = MiniPlayerWindowController.bottomLeftFrame()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
            window.setFrame(self.centeredFrame(), display: false)
            NSApp.setActivationPolicy(.accessory)
            PocketMusicUIState.shared.windowVisible = false

            if let state = PlaybackEngine.shared.state {
                MiniPlayerWindowController.shared.show(
                    state: state,
                    track: PlaybackEngine.shared.currentTrack
                )
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        collapseToMiniPlayer()
        return false
    }
}
