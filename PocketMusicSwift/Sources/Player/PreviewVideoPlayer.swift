import AVFoundation
import AppKit

@MainActor
final class PreviewVideoPlayer: NSView {
    var onReady: (() -> Void)?
    var onFailed: (() -> Void)?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var videoFill = false
    private var didStart = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func play(url: URL, videoFill: Bool = false) {
        self.videoFill = videoFill
        didStart = false
        stop(clearCallbacks: false)

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = videoFill ? 4 : 2

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        avPlayer.actionAtItemEnd = .none

        let layer = AVPlayerLayer(player: avPlayer)
        layer.videoGravity = videoFill ? .resizeAspectFill : .resizeAspect
        layer.frame = bounds
        layer.drawsAsynchronously = true
        self.layer?.addSublayer(layer)

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            avPlayer?.play()
        }

        statusObserver = item.observe(\.status, options: .new) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item.status == .failed else { return }
                self.stop()
                self.onFailed?()
            }
        }

        bufferObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: .new) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, !self.didStart, item.isPlaybackLikelyToKeepUp || item.status == .readyToPlay else { return }
                self.beginPlayback(avPlayer)
            }
        }

        player = avPlayer
        playerLayer = layer
        isHidden = false
        layoutVideo()

        // Yerel dosya — hemen başlat
        if url.isFileURL {
            beginPlayback(avPlayer)
        }
    }

    private func beginPlayback(_ avPlayer: AVPlayer) {
        guard !didStart else { return }
        didStart = true
        alphaValue = 1
        layoutVideo()
        avPlayer.play()
        onReady?()
    }

    func stop(clearCallbacks: Bool = true) {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        statusObserver?.invalidate()
        statusObserver = nil
        bufferObserver?.invalidate()
        bufferObserver = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        didStart = false
        isHidden = true
        if clearCallbacks {
            onReady = nil
            onFailed = nil
        }
    }

    override func layout() {
        super.layout()
        layoutVideo()
    }

    private func layoutVideo() {
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        playerLayer.videoGravity = videoFill ? .resizeAspectFill : .resizeAspect
        CATransaction.commit()
    }
}
