#!/Users/ali_new/PocketMusic/.venv/bin/python3
"""Spotlight / URL handler — video ID ile anında stream oynat."""

from __future__ import annotations

import sys

from common import ensure_bar_running, play_by_id
from spotlight import index_tracks, search_tracks


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("Kullanım: play_id.py VIDEO_ID")

    video_id = sys.argv[1].strip()
    ensure_bar_running()
    state = play_by_id(video_id)
    if not state:
        sys.exit(f"Parça bulunamadı: {video_id}")
    print(f"▶ {state.title}")


if __name__ == "__main__":
    main()
