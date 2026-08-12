"""Sol alt köşe — Apple Music tarzı glass mini player."""

from __future__ import annotations

import os

import AppKit
import objc
import Quartz

from common import is_paused, mpv_alive, read_state, stop_playback, toggle_pause

W, H = 300, 380
MARGIN = 22
ART = 248


def _symbol(name: str, size: float = 16) -> AppKit.NSImage | None:
    img = AppKit.NSImage.imageWithSystemSymbolName_accessibilityDescription_(name, name)
    if img is None:
        return None
    cfg = AppKit.NSImageSymbolConfiguration.configurationWithPointSize_weight_(
        size, AppKit.NSFontWeightSemibold
    )
    return img.imageWithSymbolConfiguration_(cfg)


def _bottom_left_frame() -> AppKit.NSRect:
    screen = AppKit.NSScreen.mainScreen()
    frame = screen.visibleFrame() if screen else AppKit.NSMakeRect(0, 0, 1440, 900)
    x = frame.origin.x + MARGIN
    y = frame.origin.y + MARGIN
    return AppKit.NSMakeRect(x, y, W, H)


def bottom_left_frame() -> AppKit.NSRect:
    return _bottom_left_frame()


class MiniPlayerController(AppKit.NSObject):
    panel = objc.ivar()
    art_view = objc.ivar()
    blur_bg = objc.ivar()
    title_label = objc.ivar()
    artist_label = objc.ivar()
    play_btn = objc.ivar()
    stop_btn = objc.ivar()
    progress = objc.ivar()
    _track_key = objc.ivar()
    _timer = objc.ivar()

    @classmethod
    def shared(cls):
        if cls._inst is None:
            cls._inst = cls.alloc().init()
        return cls._inst

    _inst = None

    def init(self):
        self = objc.super(MiniPlayerController, self).init()
        if self is None:
            return None
        self.panel = None
        self._track_key = ""
        self._timer = None
        return self

    def _make_button(self, symbol: str, x: float, action) -> AppKit.NSButton:
        btn = AppKit.NSButton.alloc().initWithFrame_(AppKit.NSMakeRect(x, 14, 36, 36))
        btn.setBezelStyle_(AppKit.NSBezelStyleRegularSquare)
        btn.setBordered_(False)
        btn.setImage_(_symbol(symbol, 18))
        btn.setImageScaling_(AppKit.NSImageScaleProportionallyDown)
        btn.setTarget_(self)
        btn.setAction_(action)
        btn.setWantsLayer_(True)
        btn.layer().setCornerRadius_(18)
        btn.setAlphaValue_(0.9)
        return btn

    def _build(self) -> None:
        panel = AppKit.NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            _bottom_left_frame(),
            AppKit.NSWindowStyleMaskBorderless,
            AppKit.NSBackingStoreBuffered,
            False,
        )
        panel.setLevel_(AppKit.NSFloatingWindowLevel)
        panel.setCollectionBehavior_(
            AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
            | AppKit.NSWindowCollectionBehaviorStationary
            | AppKit.NSWindowCollectionBehaviorIgnoresCycle
        )
        panel.setOpaque_(False)
        panel.setBackgroundColor_(AppKit.NSColor.clearColor())
        panel.setHasShadow_(True)
        panel.setMovableByWindowBackground_(False)
        panel.setHidesOnDeactivate_(False)

        root = AppKit.NSView.alloc().initWithFrame_(AppKit.NSMakeRect(0, 0, W, H))
        root.setWantsLayer_(True)
        root.layer().setCornerRadius_(22)
        root.layer().setMasksToBounds_(True)
        root.layer().setBorderWidth_(0.5)
        root.layer().setBorderColor_(
            AppKit.NSColor.whiteColor().colorWithAlphaComponent_(0.25).CGColor()
        )

        glass = AppKit.NSVisualEffectView.alloc().initWithFrame_(root.bounds())
        glass.setAutoresizingMask_(AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable)
        glass.setMaterial_(AppKit.NSVisualEffectMaterialHUDWindow)
        glass.setBlendingMode_(AppKit.NSVisualEffectBlendingModeBehindWindow)
        glass.setState_(AppKit.NSVisualEffectStateActive)
        root.addSubview_(glass)

        art_wrap = AppKit.NSView.alloc().initWithFrame_(
            AppKit.NSMakeRect((W - ART) / 2, H - ART - 58, ART, ART)
        )
        art_wrap.setWantsLayer_(True)
        art_wrap.layer().setCornerRadius_(16)
        art_wrap.layer().setMasksToBounds_(True)

        self.blur_bg = AppKit.NSImageView.alloc().initWithFrame_(art_wrap.bounds())
        self.blur_bg.setImageScaling_(AppKit.NSImageScaleAxesIndependently)
        self.blur_bg.setWantsLayer_(True)
        art_wrap.addSubview_(self.blur_bg)

        blur_fx = AppKit.NSVisualEffectView.alloc().initWithFrame_(art_wrap.bounds())
        blur_fx.setMaterial_(AppKit.NSVisualEffectMaterialContentBackground)
        blur_fx.setBlendingMode_(AppKit.NSVisualEffectBlendingModeWithinWindow)
        blur_fx.setState_(AppKit.NSVisualEffectStateActive)
        blur_fx.setAlphaValue_(0.35)
        art_wrap.addSubview_(blur_fx)

        self.art_view = AppKit.NSImageView.alloc().initWithFrame_(
            AppKit.NSMakeRect(0, 0, ART, ART)
        )
        self.art_view.setImageScaling_(AppKit.NSImageScaleProportionallyUpOrDown)
        self.art_view.setWantsLayer_(True)
        art_wrap.addSubview_(self.art_view)

        gradient = AppKit.CAGradientLayer.layer()
        gradient.setFrame_(AppKit.NSMakeRect(0, 0, ART, ART))
        gradient.setColors_(
            [
                AppKit.NSColor.clearColor().CGColor(),
                AppKit.NSColor.blackColor().colorWithAlphaComponent_(0.45).CGColor(),
            ]
        )
        gradient.setLocations_([0.55, 1.0])
        art_wrap.layer().addSublayer_(gradient)

        root.addSubview_(art_wrap)
        self._art_wrap = art_wrap

        self.title_label = AppKit.NSTextField.labelWithString_("")
        self.title_label.setFont_(AppKit.NSFont.systemFontOfSize_weight_(13, AppKit.NSFontWeightSemibold))
        self.title_label.setTextColor_(AppKit.NSColor.labelColor())
        self.title_label.setFrame_(AppKit.NSMakeRect(16, 88, W - 32, 18))
        self.title_label.setLineBreakMode_(AppKit.NSLineBreakByTruncatingTail)
        root.addSubview_(self.title_label)

        self.artist_label = AppKit.NSTextField.labelWithString_("")
        self.artist_label.setFont_(AppKit.NSFont.systemFontOfSize_(11))
        self.artist_label.setTextColor_(AppKit.NSColor.secondaryLabelColor())
        self.artist_label.setFrame_(AppKit.NSMakeRect(16, 70, W - 32, 16))
        self.artist_label.setLineBreakMode_(AppKit.NSLineBreakByTruncatingTail)
        root.addSubview_(self.artist_label)

        self.progress = AppKit.NSProgressIndicator.alloc().initWithFrame_(
            AppKit.NSMakeRect(16, 58, W - 32, 3)
        )
        self.progress.setStyle_(AppKit.NSProgressIndicatorStyleBar)
        self.progress.setIndeterminate_(False)
        self.progress.setMinValue_(0)
        self.progress.setMaxValue_(1)
        self.progress.setDoubleValue_(0)
        self.progress.setAlphaValue_(0.7)
        root.addSubview_(self.progress)

        self.play_btn = self._make_button("pause.fill", 96, "togglePlay:")
        self.stop_btn = self._make_button("stop.fill", 168, "stopPlay:")
        root.addSubview_(self.play_btn)
        root.addSubview_(self.stop_btn)

        panel.setContentView_(root)
        self.panel = panel

    def _load_cover(self, path: str | None) -> AppKit.NSImage | None:
        if path and os.path.exists(path):
            return AppKit.NSImage.alloc().initWithContentsOfFile_(path)
        raw = path.replace("_icon.png", "_raw.jpg") if path else ""
        if raw and os.path.exists(raw):
            return AppKit.NSImage.alloc().initWithContentsOfFile_(raw)
        return None

    def _start_preview_animation(self) -> None:
        layer = self.art_view.layer()
        layer.removeAnimationForKey_("breathe")
        anim = Quartz.CABasicAnimation.animationWithKeyPath_("transform.scale")
        anim.setFromValue_(1.0)
        anim.setToValue_(1.07)
        anim.setDuration_(5.0)
        anim.setAutoreverses_(True)
        anim.setRepeatCount_(1e9)
        anim.setTimingFunction_(
            Quartz.CAMediaTimingFunction.functionWithName_(
                Quartz.kCAMediaTimingFunctionEaseInEaseOut
            )
        )
        layer.addAnimation_forKey_(anim, "breathe")

        bg_layer = self.blur_bg.layer()
        bg_layer.removeAnimationForKey_("drift")
        drift = Quartz.CABasicAnimation.animationWithKeyPath_("transform.translation.x")
        drift.setFromValue_(-6)
        drift.setToValue_(6)
        drift.setDuration_(7.0)
        drift.setAutoreverses_(True)
        drift.setRepeatCount_(1e9)
        bg_layer.addAnimation_forKey_(drift, "drift")

    def _slide_in(self, morph: bool = False) -> None:
        frame = _bottom_left_frame()
        self.panel.setFrame_display_(frame, True)
        self.panel.setAlphaValue_(0.0)
        self.panel.orderFrontRegardless()
        duration = 0.45 if morph else 0.35
        AppKit.NSAnimationContext.beginGrouping()
        AppKit.NSAnimationContext.currentContext().setDuration_(duration)
        self.panel.animator().setAlphaValue_(1.0)
        AppKit.NSAnimationContext.endGrouping()

    @objc.python_method
    def show_with_state(self, state: dict, morph: bool = False) -> None:
        if self.panel is None:
            self._build()

        if hasattr(state, "__dataclass_fields__"):
            from dataclasses import asdict
            state = asdict(state)

        key = state.get("url", "")
        if key != self._track_key:
            self._track_key = key
            cover = self._load_cover(state.get("thumbnail_path"))
            if cover:
                self.art_view.setImage_(cover)
                self.blur_bg.setImage_(cover)
                self._start_preview_animation()

        self.title_label.setStringValue_(state.get("title", "")[:48])
        self.artist_label.setStringValue_(state.get("artist", "")[:48])
        self._update_play_icon()

        if not self.panel.isVisible():
            self._slide_in(morph=morph)
        else:
            self.panel.setFrame_display_(_bottom_left_frame(), True)

        self._start_timer()

    def _update_play_icon(self) -> None:
        sym = "play.fill" if is_paused() else "pause.fill"
        self.play_btn.setImage_(_symbol(sym, 18))

    def _start_timer(self) -> None:
        if self._timer is not None:
            return
        self._timer = AppKit.NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.5, self, "tick:", None, True
        )

    def _stop_timer(self) -> None:
        if self._timer is not None:
            self._timer.invalidate()
            self._timer = None

    def tick_(self, _) -> None:
        state = read_state()
        if not state or not mpv_alive(state.get("mpv_pid")):
            self.hide()
            return
        self._update_play_icon()
        from common import mpv_ipc

        pos = mpv_ipc(["get_property", "time-pos"])
        dur = mpv_ipc(["get_property", "duration"])
        if pos and dur and dur.get("data"):
            total = float(dur["data"] or 0)
            if total > 0 and pos.get("data") is not None:
                self.progress.setDoubleValue_(float(pos["data"]) / total)

    def hide(self) -> None:
        self._stop_timer()
        self._track_key = ""
        if self.panel is not None and self.panel.isVisible():
            self.panel.orderOut_(None)

    def togglePlay_(self, _) -> None:
        toggle_pause()
        self._update_play_icon()

    def stopPlay_(self, _) -> None:
        stop_playback()
        self.hide()


def sync_mini_player() -> None:
    state = read_state()
    if state and mpv_alive(state.get("mpv_pid")):
        MiniPlayerController.shared().show_with_state(state)
    else:
        MiniPlayerController.shared().hide()
