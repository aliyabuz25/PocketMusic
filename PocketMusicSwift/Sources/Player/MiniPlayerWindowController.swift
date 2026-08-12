import AppKit
import QuartzCore

@MainActor
final class MiniPlayerWindowController: NSWindowController {
    static let shared = MiniPlayerWindowController()

    static let width: CGFloat = 320
    static let height: CGFloat = 430
    static let margin: CGFloat = 22
    static let artHeight: CGFloat = 240
    static let cornerRadius: CGFloat = 28

    private static let originXKey = "miniPlayerOriginX"
    private static let originYKey = "miniPlayerOriginY"

    private var card: NSView!
    private var artContainer: ArtMediaView!
    private var titleLabel: NSTextField!
    private var artistLabel: NSTextField!
    private var timeLeft: NSTextField!
    private var timeRight: NSTextField!
    private var progressTrack: NSView!
    private var progressFill: NSView!
    private var favoriteBtn: NSButton!
    private var playBtn: NSButton!
    private var stopBtn: NSButton!
    private var timer: Timer?
    private var trackKey = ""
    private var currentTrack: Track?
    private var userPlaced = false

    private init() {
        super.init(window: nil)
        buildWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func bottomLeftFrame() -> NSRect {
        if let saved = savedFrame() { return saved }
        guard let screen = NSScreen.main else {
            return NSRect(x: margin, y: margin, width: width, height: height)
        }
        let vf = screen.visibleFrame
        return NSRect(x: vf.minX + margin, y: vf.minY + margin, width: width, height: height)
    }

    private static func savedFrame() -> NSRect? {
        let d = UserDefaults.standard
        guard d.object(forKey: originXKey) != nil else { return nil }
        return NSRect(
            x: d.double(forKey: originXKey),
            y: d.double(forKey: originYKey),
            width: width,
            height: height
        )
    }

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        let d = UserDefaults.standard
        d.set(frame.origin.x, forKey: Self.originXKey)
        d.set(frame.origin.y, forKey: Self.originYKey)
        userPlaced = true
    }

    private func buildWindow() {
        let panel = NSPanel(
            contentRect: Self.bottomLeftFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        let root = MiniPlayerRootView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        root.onMoved = { [weak self] in self?.saveFrame() }
        root.wantsLayer = true
        applySoftCorners(to: root.layer, radius: Self.cornerRadius, mask: false)
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = 0.28
        root.layer?.shadowRadius = 28
        root.layer?.shadowOffset = CGSize(width: 0, height: -6)

        card = NSView(frame: root.bounds)
        card.wantsLayer = true
        applySoftCorners(to: card.layer, radius: Self.cornerRadius, mask: true)
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        card.autoresizingMask = [.width, .height]
        root.addSubview(card)

        let glass = NSVisualEffectView(frame: card.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        card.addSubview(glass)

        artContainer = ArtMediaView(frame: NSRect(x: 0, y: Self.height - Self.artHeight, width: Self.width, height: Self.artHeight))
        card.addSubview(artContainer)

        let metaY: CGFloat = 108
        titleLabel = label("", size: 15, weight: .semibold, y: metaY + 28, h: 20)
        artistLabel = label("", size: 12, weight: .regular, y: metaY + 10, h: 16)
        artistLabel.textColor = .secondaryLabelColor
        card.addSubview(titleLabel)
        card.addSubview(artistLabel)

        timeLeft = label("0:00", size: 10, weight: .medium, y: 78, h: 14)
        timeRight = label("0:00", size: 10, weight: .medium, y: 78, h: 14)
        timeLeft.textColor = .tertiaryLabelColor
        timeRight.textColor = .tertiaryLabelColor
        timeRight.alignment = .right
        timeRight.frame.origin.x = Self.width - 48
        timeRight.frame.size.width = 32
        card.addSubview(timeLeft)
        card.addSubview(timeRight)

        progressTrack = NSView(frame: NSRect(x: 16, y: 92, width: Self.width - 32, height: 4))
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        applySoftCorners(to: progressTrack.layer, radius: 2, mask: true)
        card.addSubview(progressTrack)

        progressFill = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 4))
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        applySoftCorners(to: progressFill.layer, radius: 2, mask: true)
        progressTrack.addSubview(progressFill)

        favoriteBtn = makeButton(symbol: "heart", x: 52, action: #selector(toggleFavorite))
        playBtn = makeButton(symbol: "pause.fill", x: 128, action: #selector(togglePlay))
        stopBtn = makeButton(symbol: "stop.fill", x: 204, action: #selector(stopPlay))

        let expandBtn = makeButton(symbol: "arrow.up.left.and.arrow.down.right", x: Self.width - 48, action: #selector(expandToApp))
        expandBtn.frame.origin = NSPoint(x: Self.width - 48, y: Self.height - 48)
        expandBtn.toolTip = "Pocket Music'e geç"
        card.addSubview(favoriteBtn)
        card.addSubview(playBtn)
        card.addSubview(stopBtn)
        card.addSubview(expandBtn)

        panel.contentView = root
        window = panel
    }

    private func applySoftCorners(to layer: CALayer?, radius: CGFloat, mask: Bool) {
        guard let layer else { return }
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        if mask { layer.masksToBounds = true }
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, y: CGFloat, h: CGFloat) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.frame = NSRect(x: 16, y: y, width: Self.width - 32, height: h)
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    private func makeButton(symbol: String, x: CGFloat, action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: x, y: 18, width: 40, height: 40))
        btn.isBordered = false
        btn.bezelStyle = .regularSquare
        btn.target = self
        btn.action = action
        btn.image = symbolImage(symbol)
        btn.imageScaling = .scaleProportionallyDown
        btn.wantsLayer = true
        applySoftCorners(to: btn.layer, radius: 20, mask: true)
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        return btn
    }

    private func symbolImage(_ name: String, fill: Bool = false) -> NSImage? {
        var cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        if fill { cfg = cfg.applying(.init(paletteColors: [.systemPink])) }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    }

    func showPending(track: Track) {
        currentTrack = track
        trackKey = track.id
        titleLabel.stringValue = String(track.title.prefix(52))
        artistLabel.stringValue = String(track.artist.prefix(52))
        artContainer.stopVideo()
        artContainer.setArtworkPlaceholder()
        updateFavoriteIcon()

        if let thumb = track.thumbnailURL, let url = URL(string: thumb),
           let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
            artContainer.setArtwork(img)
        } else {
            loadArtwork(path: "", trackId: track.id)
        }

        PreviewPrefetcher.prefetch(track)
        loadPreviewVideo(urlString: nil, isVideo: false, trackId: track.id)

        if window?.isVisible != true {
            let frame = Self.bottomLeftFrame()
            window?.setFrame(frame, display: true)
            window?.alphaValue = 0
            window?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window?.animator().alphaValue = 1
            }
        }
        startTimer()
    }

    func show(state: PlaybackState, track: Track? = nil, morph: Bool = false) {
        trackKey = state.trackId

        if let track { currentTrack = track }
        else if currentTrack == nil || currentTrack?.id != state.trackId {
            currentTrack = Track(
                id: state.trackId,
                title: state.title,
                artist: state.artist,
                url: state.url,
                duration: nil,
                thumbnailURL: "https://i.ytimg.com/vi/\(state.trackId)/hqdefault.jpg"
            )
        }

        artContainer.stopVideo()
        loadArtwork(path: state.thumbnailPath, trackId: state.trackId)
        loadPreviewVideo(urlString: state.previewVideoURL, isVideo: state.previewIsVideo, trackId: state.trackId)

        titleLabel.stringValue = String(state.title.prefix(52))
        artistLabel.stringValue = String(state.artist.prefix(52))
        updatePlayIcon()
        updateFavoriteIcon()

        if window?.isVisible != true {
            let frame = Self.bottomLeftFrame()
            window?.setFrame(frame, display: true)
            window?.alphaValue = 0
            window?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = morph ? 0.5 : 0.38
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window?.animator().alphaValue = 1
            }
        }
        startTimer()
    }

    private func loadArtwork(path: String, trackId: String) {
        if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
            artContainer.setArtwork(img)
        }

        guard let track = currentTrack else {
            artContainer.setArtworkPlaceholder()
            return
        }

        Task {
            // Apple Music kapak — resmi, yüksek çözünürlük
            if let amPath = await MusicService.downloadCatalogCover(for: track),
               let img = NSImage(contentsOfFile: amPath) {
                await MainActor.run {
                    guard self.trackKey == trackId else { return }
                    self.artContainer.setArtwork(img, style: .appleMusic)
                }
                return
            }

            if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                await MainActor.run {
                    guard self.trackKey == trackId else { return }
                    self.artContainer.setArtwork(img)
                }
                return
            }

            if let url = URL(string: track.bestThumbnailURL),
               let data = try? Data(contentsOf: url),
               let img = NSImage(data: data) {
                await MainActor.run {
                    guard self.trackKey == trackId else { return }
                    self.artContainer.setArtwork(img)
                }
            } else {
                await MainActor.run {
                    guard self.trackKey == trackId else { return }
                    self.artContainer.setArtworkPlaceholder()
                }
            }
        }
    }

    func applyPreview(_ cached: CachedPreview, trackId: String) {
        guard trackKey == trackId else { return }
        artContainer.tryCatalogPreview(url: cached.localURL, isVideo: cached.isVideo)
    }

    private func loadPreviewVideo(urlString: String?, isVideo: Bool, trackId: String) {
        let tryPlay: (URL, Bool) -> Void = { url, video in
            self.artContainer.tryCatalogPreview(url: url, isVideo: video)
        }

        if let urlString, let url = URL(string: urlString) {
            tryPlay(url, isVideo)
            return
        }

        guard let track = currentTrack else { return }
        Task {
            if let cached = await PreviewPrefetcher.wait(for: track) {
                await MainActor.run {
                    guard self.trackKey == trackId else { return }
                    tryPlay(cached.localURL, cached.isVideo)
                    if var s = PlaybackEngine.shared.state {
                        s.previewVideoURL = cached.localURL.absoluteString
                        s.previewIsVideo = cached.isVideo
                        PlaybackEngine.shared.updateState(s)
                    }
                }
            }
        }
    }

    func hide() {
        stopTimer()
        artContainer.reset()
        trackKey = ""
        currentTrack = nil
        window?.orderOut(nil)
    }

    private func updatePlayIcon() {
        let sym = PlaybackEngine.shared.isPaused ? "play.fill" : "pause.fill"
        playBtn.image = symbolImage(sym)
    }

    private func updateFavoriteIcon() {
        guard let track = currentTrack else { return }
        let fav = FavoritesStore.shared.isFavorite(track)
        favoriteBtn.image = symbolImage(fav ? "heart.fill" : "heart", fill: fav)
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard PlaybackEngine.shared.isAlive else {
            hide()
            MenuBarModel.shared.refresh()
            return
        }
        updatePlayIcon()
        let p = PlaybackEngine.shared.progress()
        let w = progressTrack.bounds.width * p
        progressFill.frame = NSRect(x: 0, y: 0, width: max(0, w), height: 4)
        timeLeft.stringValue = PlaybackEngine.shared.timeText(position: true)
        timeRight.stringValue = PlaybackEngine.shared.timeText(position: false)
    }

    @objc private func toggleFavorite() {
        guard let track = currentTrack else { return }
        FavoritesStore.shared.toggle(track)
        updateFavoriteIcon()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc private func togglePlay() {
        PlaybackEngine.shared.togglePause()
        updatePlayIcon()
        MenuBarModel.shared.refresh()
    }

    @objc private func stopPlay() {
        PlaybackEngine.shared.stop()
        hide()
        MenuBarModel.shared.refresh()
    }

    @objc private func expandToApp() {
        guard let frame = window?.frame else {
            MainWindowController.shared.present()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            window?.animator().alphaValue = 0
        } completionHandler: {
            self.hide()
            self.window?.alphaValue = 1
            MainWindowController.shared.present(from: frame)
        }
    }
}

// MARK: - Sürüklenebilir kök görünüm

private final class MiniPlayerRootView: NSView {
    var onMoved: (() -> Void)?
    private var dragMouse = NSPoint.zero
    private var dragOrigin = NSPoint.zero

    override func mouseDown(with event: NSEvent) {
        dragMouse = NSEvent.mouseLocation
        dragOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let cur = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: dragOrigin.x + cur.x - dragMouse.x,
            y: dragOrigin.y + cur.y - dragMouse.y
        ))
        onMoved?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit is NSControl { return hit }
        return self
    }
}

// MARK: - Apple Music tarzı kapak + 30sn preview

private enum ArtworkStyle {
    case standard
    case appleMusic
}

@MainActor
private final class ArtMediaView: NSView {
    private let backdrop = NSImageView()
    private let artView = NSImageView()
    private let placeholder = NSImageView()
    private let mediaPreview = PreviewVideoPlayer()
    private let gradient = GradientView()
    private let pad: CGFloat = 12
    private var style: ArtworkStyle = .standard
    private var videoMode = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor

        backdrop.imageScaling = .scaleAxesIndependently
        backdrop.imageAlignment = .alignCenter
        backdrop.autoresizingMask = [.width, .height]
        backdrop.wantsLayer = true
        backdrop.layer?.filters = [Self.blurFilter()]
        backdrop.alphaValue = 0.85
        backdrop.isHidden = true
        addSubview(backdrop)

        artView.imageScaling = .scaleProportionallyUpOrDown
        artView.imageAlignment = .alignCenter
        artView.wantsLayer = true
        addSubview(artView)

        placeholder.imageScaling = .scaleProportionallyUpOrDown
        placeholder.imageAlignment = .alignCenter
        placeholder.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        placeholder.contentTintColor = NSColor.white.withAlphaComponent(0.25)
        placeholder.autoresizingMask = [.width, .height]
        addSubview(placeholder)

        mediaPreview.isHidden = true
        addSubview(mediaPreview)

        gradient.autoresizingMask = [.width, .maxYMargin]
        addSubview(gradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func blurFilter() -> CIFilter {
        let f = CIFilter(name: "CIGaussianBlur")!
        f.setValue(22.0, forKey: kCIInputRadiusKey)
        return f
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds

        if videoMode {
            artView.isHidden = true
            mediaPreview.frame = bounds
        } else {
            mediaPreview.frame = bounds
            switch style {
            case .appleMusic:
                let side = min(bounds.width, bounds.height) - pad * 2
                artView.frame = NSRect(
                    x: (bounds.width - side) / 2,
                    y: (bounds.height - side) / 2,
                    width: side,
                    height: side
                )
                artView.layer?.cornerRadius = 10
                artView.layer?.cornerCurve = .continuous
                artView.layer?.masksToBounds = true
                artView.isHidden = artView.image == nil
            case .standard:
                artView.layer?.cornerRadius = 0
                artView.layer?.masksToBounds = false
                artView.frame = bounds.insetBy(dx: pad, dy: pad)
            }
            placeholder.frame = artView.frame
        }

        gradient.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 72)
    }

    func setArtwork(_ image: NSImage, style: ArtworkStyle = .standard) {
        self.style = style
        backdrop.image = (style == .appleMusic || videoMode) ? image : nil
        backdrop.isHidden = !(style == .appleMusic || videoMode)

        if videoMode {
            needsLayout = true
            return
        }

        artView.image = image
        artView.isHidden = false
        placeholder.isHidden = true
        needsLayout = true
    }

    func setArtworkPlaceholder() {
        artView.image = nil
        artView.isHidden = true
        placeholder.isHidden = false
        backdrop.isHidden = true
        needsLayout = true
    }

    func stopVideo() {
        videoMode = false
        mediaPreview.stop()
        artView.layer?.removeAnimation(forKey: "pulse")
        backdrop.isHidden = style != .appleMusic
        artView.isHidden = artView.image == nil
        needsLayout = true
    }

    func tryCatalogPreview(url: URL, isVideo: Bool) {
        layoutSubtreeIfNeeded()
        mediaPreview.frame = bounds

        if isVideo {
            videoMode = true
            style = .appleMusic
            backdrop.isHidden = false
            addSubview(mediaPreview, positioned: .above, relativeTo: backdrop)
            addSubview(gradient, positioned: .above, relativeTo: mediaPreview)

            mediaPreview.onReady = { [weak self] in
                guard let self else { return }
                self.artView.isHidden = true
                self.placeholder.isHidden = true
            }
            mediaPreview.onFailed = { [weak self] in
                self?.fallbackFromVideoFailure()
            }
            mediaPreview.play(url: url, videoFill: true)
        } else {
            videoMode = false
            mediaPreview.onReady = { [weak self] in
                self?.startPreviewPulse()
            }
            mediaPreview.onFailed = { [weak self] in
                self?.stopVideo()
            }
            mediaPreview.play(url: url, videoFill: false)
        }
        needsLayout = true
    }

    private func fallbackFromVideoFailure() {
        videoMode = false
        mediaPreview.stop()
        artView.isHidden = artView.image == nil
        placeholder.isHidden = artView.image != nil
        backdrop.isHidden = style != .appleMusic
        needsLayout = true
    }

    private func startPreviewPulse() {
        guard style == .appleMusic, let layer = artView.layer else { return }
        layer.removeAnimation(forKey: "pulse")
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 1.03
        anim.duration = 2.4
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "pulse")
    }

    func reset() {
        stopVideo()
        artView.image = nil
        artView.isHidden = true
        placeholder.isHidden = false
        backdrop.isHidden = true
        style = .standard
        videoMode = false
    }
}

private final class GradientView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let colors = [
            NSColor.black.withAlphaComponent(0.42).cgColor,
            NSColor.clear.cgColor,
        ] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: bounds.minY),
                end: CGPoint(x: 0, y: bounds.maxY),
                options: []
            )
        }
    }
}
