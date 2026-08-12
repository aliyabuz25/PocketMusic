"""macOS Spotlight indeksleme — arama sonuçlarını Spotlight'a ekle."""

from __future__ import annotations

import json
import threading
import urllib.request

from CoreSpotlight import CSSearchableIndex, CSSearchableItem, CSSearchableItemAttributeSet
from Foundation import NSData, NSDate, NSRunLoop, NSURL

from common import SPOTLIGHT_CACHE, SPOTLIGHT_DOMAIN, Track, ensure_dir, search_tracks


def _cache_tracks(tracks: list[Track]) -> None:
    ensure_dir()
    cache: dict[str, dict] = {}
    if SPOTLIGHT_CACHE.exists():
        try:
            cache = json.loads(SPOTLIGHT_CACHE.read_text())
        except (json.JSONDecodeError, OSError):
            cache = {}

    for t in tracks:
        cache[t.id] = {
            "id": t.id,
            "title": t.title,
            "artist": t.uploader,
            "url": t.url,
            "duration": t.duration,
            "thumbnail_url": t.thumbnail_url,
        }

    SPOTLIGHT_CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2))


def _thumb_data(track: Track) -> NSData | None:
    url = track.thumbnail_url or f"https://i.ytimg.com/vi/{track.id}/hqdefault.jpg"
    try:
        with urllib.request.urlopen(url, timeout=8) as resp:
            data = resp.read()
            return NSData.dataWithBytes_length_(data, len(data))
    except Exception:
        return None


def _item_for_track(track: Track) -> CSSearchableItem:
    attrs = CSSearchableItemAttributeSet.alloc().initWithItemContentType_("public.audio")
    attrs.setTitle_(track.title)
    attrs.setContentDescription_(f"{track.uploader} · PocketMusic")
    attrs.setKeywords_([track.title, track.uploader, "müzik", "pocketmusic", "music"])
    attrs.setDisplayName_(track.title)
    attrs.setArtist_(track.uploader)
    attrs.setContentURL_(NSURL.URLWithString_(f"pocketmusic://play/{track.id}"))

    thumb = _thumb_data(track)
    if thumb:
        attrs.setThumbnailData_(thumb)

    return CSSearchableItem.alloc().initWithUniqueIdentifier_domainIdentifier_attributeSet_(
        track.id,
        SPOTLIGHT_DOMAIN,
        attrs,
    )


def _wait_for_index(_error) -> None:
    _wait_for_index.done.set()  # type: ignore[attr-defined]


def _index_items(items: list) -> None:
    if not items:
        return
    _wait_for_index.done = threading.Event()  # type: ignore[attr-defined]
    index = CSSearchableIndex.defaultSearchableIndex()
    index.indexSearchableItems_completionHandler_(items, _wait_for_index)
    while not _wait_for_index.done.wait(timeout=0.1):  # type: ignore[attr-defined]
        NSRunLoop.currentRunLoop().runMode_beforeDate_("kCFRunLoopDefaultMode", NSDate.dateWithTimeIntervalSinceNow_(0.1))


def index_tracks(tracks: list[Track]) -> None:
    if not tracks:
        return
    _cache_tracks(tracks)
    items = [_item_for_track(t) for t in tracks]
    _index_items(items)


def index_query(query: str, limit: int = 10) -> list[Track]:
    tracks = search_tracks(query, limit=limit)
    index_tracks(tracks)
    return tracks


def clear_index() -> None:
    done = threading.Event()

    def handler(_error) -> None:
        done.set()

    index = CSSearchableIndex.defaultSearchableIndex()
    index.deleteSearchableItemsWithDomainIdentifiers_completionHandler_([SPOTLIGHT_DOMAIN], handler)
    while not done.wait(timeout=0.1):
        NSRunLoop.currentRunLoop().runMode_beforeDate_("kCFRunLoopDefaultMode", NSDate.dateWithTimeIntervalSinceNow_(0.1))
    if SPOTLIGHT_CACHE.exists():
        SPOTLIGHT_CACHE.unlink()
