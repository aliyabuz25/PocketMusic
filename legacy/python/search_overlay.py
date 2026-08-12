"""Ekran ortası sinematik arama → mini player morph."""

from __future__ import annotations

import threading

import AppKit
import objc
import Quartz

from common import ensure_bar_running, read_state, search_tracks, start_playback

SEARCH_W = 480
SEARCH_H = 64


def _center_frame() -> AppKit.NSRect:
    screen = AppKit.NSScreen.mainScreen()
    frame = screen.frame() if screen else AppKit.NSMakeRect(0, 0, 1440, 900)
    x = frame.origin.x + (frame.size.width - SEARCH_W) / 2
    y = frame.origin.y + (frame.size.height - SEARCH_H) / 2 + 60
    return AppKit.NSMakeRect(x, y, SEARCH_W, SEARCH_H)


class KeyPanel(AppKit.NSPanel):
    def canBecomeKeyWindow(self):
        return True

    def canBecomeMainWindow(self):
        return False


class SearchFieldDelegate(AppKit.NSObject):
    def initWithController_(self, controller):
        self = objc.super(SearchFieldDelegate, self).init()
        if self is None:
            return None
        self._controller = controller
        return self

    def control_textView_doCommandBySelector_(self, control, textView, commandSelector):
        if str(commandSelector) == "insertNewline:":
            self._controller.submit_query()
            return True
        return False


def search_and_play_worker(controller, query: str, gen: int) -> None:
    try:
        tracks = search_tracks(query.strip(), limit=1)
    except Exception:
        tracks = []

    if not tracks:
        controller.performSelectorOnMainThread_withObject_waitUntilDone_(
            "onSearchFailed:", message_for_gen(gen, "Bulunamadı — tekrar dene"), False
        )
        return

    ensure_bar_running()
    try:
        start_playback(tracks[0])
    except Exception:
        pass

    controller.performSelectorOnMainThread_withObject_waitUntilDone_(
        "onPlaybackReady:", gen, False
    )


def message_for_gen(gen: int, text: str) -> str:
    return f"{gen}|{text}"


class SearchOverlayController(AppKit.NSObject):
    def init(self):
        self = objc.super(SearchOverlayController, self).init()
        if self is None:
            return None
        self.panel = None
        self.field = None
        self.hint = None
        self.spinner = None
        self.monitor = None
        self._gen = 0
        self._morph_state = None
        self._morphing = False
        return self

    @classmethod
    def shared(cls):
        if cls._shared is None:
            cls._shared = cls.alloc().init()
        return cls._shared

    _shared = None

    def _build(self) -> None:
        panel = KeyPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            _center_frame(),
            AppKit.NSWindowStyleMaskBorderless,
            AppKit.NSBackingStoreBuffered,
            False,
        )
        panel.setLevel_(AppKit.NSFloatingWindowLevel + 1)
        panel.setCollectionBehavior_(
            AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
            | AppKit.NSWindowCollectionBehaviorFullScreenAuxiliary
        )
        panel.setOpaque_(False)
        panel.setBackgroundColor_(AppKit.NSColor.clearColor())
        panel.setHasShadow_(True)
        panel.setHidesOnDeactivate_(False)

        root = AppKit.NSView.alloc().initWithFrame_(AppKit.NSMakeRect(0, 0, SEARCH_W, SEARCH_H))
        root.setWantsLayer_(True)
        root.layer().setCornerRadius_(SEARCH_H / 2)

        glass = AppKit.NSVisualEffectView.alloc().initWithFrame_(root.bounds())
        glass.setAutoresizingMask_(AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable)
        glass.setMaterial_(AppKit.NSVisualEffectMaterialHUDWindow)
        glass.setBlendingMode_(AppKit.NSVisualEffectBlendingModeBehindWindow)
        glass.setState_(AppKit.NSVisualEffectStateActive)
        root.addSubview_(glass)

        sym = AppKit.NSImage.imageWithSystemSymbolName_accessibilityDescription_("music.note", "music")
        cfg = AppKit.NSImageSymbolConfiguration.configurationWithPointSize_weight_(17, AppKit.NSFontWeightMedium)
        icon = AppKit.NSImageView.alloc().initWithFrame_(AppKit.NSMakeRect(18, 20, 24, 24))
        icon.setImage_(sym.imageWithSymbolConfiguration_(cfg))
        root.addSubview_(icon)

        self.field = AppKit.NSTextField.alloc().initWithFrame_(AppKit.NSMakeRect(50, 16, SEARCH_W - 92, 32))
        self.field.setFont_(AppKit.NSFont.systemFontOfSize_weight_(19, AppKit.NSFontWeightRegular))
        self.field.setPlaceholderString_("Parça veya sanatçı adı...")
        self.field.setBezeled_(False)
        self.field.setDrawsBackground_(False)
        self.field.setEditable_(True)
        self.field.setSelectable_(True)
        self.field.setEnabled_(True)
        self.field.setFocusRingType_(AppKit.NSFocusRingTypeNone)
        root.addSubview_(self.field)

        self.spinner = AppKit.NSProgressIndicator.alloc().initWithFrame_(
            AppKit.NSMakeRect(SEARCH_W - 36, 24, 16, 16)
        )
        self.spinner.setStyle_(AppKit.NSProgressIndicatorStyleSpinning)
        self.spinner.setDisplayedWhenStopped_(False)
        root.addSubview_(self.spinner)

        self.hint = AppKit.NSTextField.labelWithString_("Enter → oynat   ·   Esc → kapat")
        self.hint.setFont_(AppKit.NSFont.systemFontOfSize_(10))
        self.hint.setTextColor_(AppKit.NSColor.secondaryLabelColor())
        self.hint.setFrame_(AppKit.NSMakeRect(50, 2, SEARCH_W - 60, 12))
        root.addSubview_(self.hint)

        delegate = SearchFieldDelegate.alloc().initWithController_(self)
        self.field.setDelegate_(delegate)
        self._field_delegate = delegate

        panel.setContentView_(root)
        self.panel = panel
        self._root = root

    @objc.python_method
    def set_busy(self, busy: bool) -> None:
        self.field.setEnabled_(not busy)
        if busy:
            self.spinner.startAnimation_(None)
        else:
            self.spinner.stopAnimation_(None)

    @objc.python_method
    def set_hint(self, text: str) -> None:
        self.hint.setStringValue_(text)

    @objc.python_method
    def on_search_failed(self, gen: int, message: str) -> None:
        if gen != self._gen:
            return
        self.set_busy(False)
        self.set_hint(message)

    def onSearchFailed_(self, payload) -> None:
        text = str(payload or "")
        if "|" in text:
            gen_s, msg = text.split("|", 1)
            self.on_search_failed(int(gen_s), msg)
        else:
            self.on_search_failed(self._gen, text or "Hata")

    def onPlaybackReady_(self, gen_obj) -> None:
        gen = int(gen_obj) if gen_obj is not None else -1
        if gen != self._gen:
            return
        state = read_state()
        if state:
            self.morph_to_mini_player(state)
        else:
            self.on_search_failed(gen, "Oynatılamadı")

    @objc.python_method
    def submit_query(self) -> None:
        query = self.field.stringValue().strip()
        if len(query) < 2:
            self.set_hint("En az 2 karakter yaz...")
            return
        self._gen += 1
        gen = self._gen
        self.set_busy(True)
        self.set_hint("Aranıyor...")
        threading.Thread(target=search_and_play_worker, args=(self, query, gen), daemon=True).start()

    @objc.python_method
    def morph_to_mini_player(self, state: dict) -> None:
        if getattr(self, "_morphing", False):
            return
        if not state:
            self.on_search_failed(self._gen, "Oynatılamadı")
            return

        self._morphing = True
        from mini_player import MiniPlayerController

        self._remove_monitor()
        self._morph_state = state
        self.set_busy(False)
        self.set_hint("Oynatılıyor...")
        self.field.setStringValue_(state.get("title", "")[:45])

        target = MiniPlayerController.bottom_left_frame()

        # Sinematik morph: ortadan sol alta kay + büyü
        AppKit.NSAnimationContext.beginGrouping()
        ctx = AppKit.NSAnimationContext.currentContext()
        ctx.setDuration_(0.55)
        ctx.setTimingFunction_(
            Quartz.CAMediaTimingFunction.functionWithName_(
                Quartz.kCAMediaTimingFunctionEaseInEaseOut
            )
        )
        self.panel.animator().setFrame_display_(target, True)
        self._root.layer().setCornerRadius_(22)
        AppKit.NSAnimationContext.endGrouping()

        self.performSelector_withObject_afterDelay_("finishMorph:", None, 0.56)

    def finishMorph_(self, _) -> None:
        from mini_player import MiniPlayerController

        state = self._morph_state
        self._morph_state = None

        self.panel.orderOut_(None)
        self.panel.setAlphaValue_(1.0)
        self.panel.setFrame_display_(_center_frame(), False)
        self._root.layer().setCornerRadius_(SEARCH_H / 2)

        if state:
            MiniPlayerController.shared().show_with_state(state, morph=True)
        self._morphing = False

    def _key_handler(self, event):
        if event.keyCode() == 53:
            self.hide()
            return None
        return event

    def _install_monitor(self) -> None:
        if self.monitor is None:
            self.monitor = AppKit.NSEvent.addLocalMonitorForEventsMatchingMask_handler_(
                AppKit.NSEventMaskKeyDown, self._key_handler
            )

    def _remove_monitor(self) -> None:
        if self.monitor is not None:
            AppKit.NSEvent.removeMonitor_(self.monitor)
            self.monitor = None

    def show(self) -> None:
        if self.panel is None:
            self._build()
        self._gen += 1
        self.field.setStringValue_("")
        self.set_busy(False)
        self.set_hint("Enter → oynat   ·   Esc → kapat")
        self.panel.setFrame_display_(_center_frame(), False)
        self.panel.setAlphaValue_(1.0)
        self.panel.makeKeyAndOrderFront_(None)
        AppKit.NSApp.activateIgnoringOtherApps_(True)
        self.panel.makeFirstResponder_(self.field)
        self._install_monitor()

    def hide(self) -> None:
        self._remove_monitor()
        self._gen += 1
        self._morphing = False
        if self.panel is not None:
            self.panel.orderOut_(None)


def show_search() -> None:
    SearchOverlayController.shared().show()
