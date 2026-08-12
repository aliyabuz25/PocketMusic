#!/Users/ali_new/PocketMusic/.venv/bin/python3
"""PocketMusic Spotlight URL handler — pocketmusic://play/VIDEO_ID"""

from __future__ import annotations

import sys
from urllib.parse import urlparse

import AppKit
import objc

from common import ensure_bar_running, play_by_id
from spotlight import index_query


def handle_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "pocketmusic":
        return

    host = (parsed.netloc or "").lower()
    path = parsed.path.strip("/")

    if host == "search" and path:
        query = path.replace("+", " ")
        index_query(query, limit=10)
        return

    video_id = path or host
    if not video_id:
        return

    ensure_bar_running()
    play_by_id(video_id)


class AppDelegate(AppKit.NSObject):
    def applicationDidFinishLaunching_(self, notification) -> None:
        AppKit.NSApp.setActivationPolicy_(AppKit.NSApplicationActivationPolicyProhibited)

    def application_openURLs_(self, app, urls) -> None:
        for url in urls:
            handle_url(str(url))
        AppKit.NSApp.terminate_(None)

    def applicationShouldTerminateAfterLastWindowClosed_(self, sender) -> bool:
        return True


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1].startswith("pocketmusic://"):
        handle_url(sys.argv[1])
        return

    app = AppKit.NSApplication.sharedApplication()
    delegate = AppDelegate.alloc().init()
    app.setDelegate_(delegate)
    app.run()


if __name__ == "__main__":
    main()
