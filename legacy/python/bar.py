#!/Users/ali_new/PocketMusic/.venv/bin/python3
"""PocketMusic menü çubuğu — kapak + oynatma kontrolleri."""

from __future__ import annotations

import os

import rumps

from common import (
    BAR_PID_FILE,
    POCKET_DIR,
    clear_state,
    consume_search_request,
    is_paused,
    mpv_alive,
    read_state,
    stop_playback,
    toggle_pause,
)
from icons import icon, status_icon
from mini_player import sync_mini_player
from search_overlay import show_search


class PocketMusicBar(rumps.App):
    def __init__(self) -> None:
        idle = status_icon("music")
        super().__init__("PocketMusic", title="", icon=idle, quit_button=None, template=True)

        self.search_item = rumps.MenuItem(
            "Ara",
            callback=self.on_search,
            key="k",
            icon=icon("search"),
            template=True,
        )
        self.now_playing = rumps.MenuItem("Şimdi Çalan", callback=None)
        self.track_item = rumps.MenuItem("Parça seçilmedi", callback=None)
        self.artist_item = rumps.MenuItem("Ara butonuna tıkla", callback=None)
        self.play_item = rumps.MenuItem(
            "Oynat",
            callback=self.on_play_pause,
            icon=icon("play"),
            template=True,
        )
        self.stop_item = rumps.MenuItem(
            "Durdur",
            callback=self.on_stop,
            icon=icon("stop"),
            template=True,
        )
        self.quit_item = rumps.MenuItem(
            "Çıkış",
            callback=self.on_quit,
            icon=icon("power"),
            template=True,
        )

        self.menu = [
            self.search_item,
            None,
            self.now_playing,
            self.track_item,
            self.artist_item,
            None,
            self.play_item,
            self.stop_item,
            None,
            self.quit_item,
        ]

        POCKET_DIR.mkdir(parents=True, exist_ok=True)
        BAR_PID_FILE.write_text(str(os.getpid()))

        self.timer = rumps.Timer(self.refresh, 1)
        self.timer.start()
        self.refresh(None)

    def _set_idle(self) -> None:
        self.title = ""
        self.icon = status_icon("music")
        self.template = True
        self.now_playing.title = "Şimdi Çalan"
        self.track_item.title = "Parça yok"
        self.artist_item.title = "Ara → isim yaz → Enter"

    def refresh(self, _) -> None:
        if consume_search_request():
            show_search()

        state = read_state()
        if not state or not mpv_alive(state.get("mpv_pid")):
            self._set_idle()
            sync_mini_player()
            if state and not mpv_alive(state.get("mpv_pid")):
                clear_state()
            return

        # Arama açıkken müzik başladıysa → mini playera morph
        try:
            from search_overlay import SearchOverlayController
            search = SearchOverlayController.shared()
            if search.panel is not None and search.panel.isVisible():
                search.morph_to_mini_player(state)
                return
        except Exception:
            pass

        cover = state.get("thumbnail_path")
        if cover and os.path.exists(cover):
            self.icon = cover
            self.template = False
        else:
            self.icon = status_icon("music")
            self.template = True
        self.title = ""

        self.now_playing.title = "Şimdi Çalan"
        self.track_item.title = state.get("title", "Bilinmeyen")[:55]
        self.artist_item.title = state.get("artist", "")[:55]

        paused = is_paused()
        if paused:
            self.play_item.title = "Oynat"
            self.play_item.icon = icon("play")
        else:
            self.play_item.title = "Duraklat"
            self.play_item.icon = icon("pause")

        sync_mini_player()

    def on_search(self, _) -> None:
        show_search()

    def on_play_pause(self, _) -> None:
        if read_state():
            toggle_pause()
            self.refresh(None)

    def on_stop(self, _) -> None:
        stop_playback()
        self.refresh(None)

    def on_quit(self, _) -> None:
        BAR_PID_FILE.unlink(missing_ok=True)
        rumps.quit_application()


def main() -> None:
    PocketMusicBar().run()


if __name__ == "__main__":
    main()
