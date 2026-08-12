import AppKit

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SearchWindowController: NSWindowController {
    static let shared = SearchWindowController()

    private let searchW: CGFloat = 480
    private let searchH: CGFloat = 64
    private var field: NSTextField!
    private var hint: NSTextField!
    private var spinner: NSProgressIndicator!
    private var rootView: NSView!
    private var gen = 0
    private var morphing = false
    private var keyMonitor: Any?

    private init() {
        super.init(window: nil)
        buildWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func centerFrame() -> NSRect {
        guard let screen = NSScreen.main else { return NSRect(x: 200, y: 200, width: searchW, height: searchH) }
        let f = screen.frame
        return NSRect(
            x: f.midX - searchW / 2,
            y: f.midY - searchH / 2 + 60,
            width: searchW,
            height: searchH
        )
    }

    private func buildWindow() {
        let panel = KeyPanel(
            contentRect: centerFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        rootView = NSView(frame: NSRect(x: 0, y: 0, width: searchW, height: searchH))
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = searchH / 2

        let glass = NSVisualEffectView(frame: rootView.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        rootView.addSubview(glass)

        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        if let sym = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let icon = NSImageView(frame: NSRect(x: 18, y: 20, width: 24, height: 24))
            icon.image = sym
            rootView.addSubview(icon)
        }

        field = NSTextField(frame: NSRect(x: 50, y: 16, width: searchW - 92, height: 32))
        field.font = .systemFont(ofSize: 19)
        field.placeholderString = "Parça veya sanatçı adı..."
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        rootView.addSubview(field)

        spinner = NSProgressIndicator(frame: NSRect(x: searchW - 36, y: 24, width: 16, height: 16))
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        rootView.addSubview(spinner)

        hint = NSTextField(labelWithString: "Enter → oynat   ·   Esc → kapat")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 50, y: 2, width: searchW - 60, height: 12)
        rootView.addSubview(hint)

        panel.contentView = rootView
        window = panel
    }

    func showSearch() {
        gen += 1
        morphing = false
        field.stringValue = ""
        setBusy(false)
        hint.stringValue = "Enter → oynat   ·   Esc → kapat"
        window?.setFrame(centerFrame(), display: false)
        window?.alphaValue = 0
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(field)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window?.animator().alphaValue = 1
        }

        installKeyMonitor()
    }

    func hideSearch() {
        removeKeyMonitor()
        gen += 1
        morphing = false
        window?.orderOut(nil)
    }

    private func setBusy(_ busy: Bool) {
        field.isEnabled = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func submit() {
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            hint.stringValue = "En az 2 karakter..."
            return
        }
        gen += 1
        let currentGen = gen
        setBusy(true)
        hint.stringValue = "Aranıyor..."

        Task {
            guard let track = await MusicService.search(query: query) else {
                await MainActor.run {
                    guard currentGen == self.gen else { return }
                    self.setBusy(false)
                    self.hint.stringValue = "Bulunamadı"
                }
                return
            }
            await MainActor.run {
                guard currentGen == self.gen else { return }
                self.setBusy(false)
                self.hideSearch()
            }
            await PlaybackLauncher.play(track)
        }
    }

    private func morphToMiniPlayer(state: PlaybackState, track: Track) {
        guard !morphing else { return }
        morphing = true
        setBusy(false)
        hint.stringValue = "Oynatılıyor..."
        field.stringValue = state.title

        let target = MiniPlayerWindowController.bottomLeftFrame()
        removeKeyMonitor()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.window?.animator().setFrame(target, display: true)
            self.rootView.layer?.cornerRadius = 22
        } completionHandler: {
            Task { @MainActor in
                self.window?.orderOut(nil)
                self.rootView.layer?.cornerRadius = self.searchH / 2
                self.window?.setFrame(self.centerFrame(), display: false)
                self.window?.alphaValue = 1
                self.morphing = false
                MiniPlayerWindowController.shared.show(state: state, track: track, morph: true)
                MenuBarModel.shared.refresh()
            }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hideSearch()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}

extension SearchWindowController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        return false
    }
}
