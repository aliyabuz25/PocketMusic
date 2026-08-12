"""PocketMusic paylaşılan yardımcılar."""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path

POCKET_DIR = Path.home() / ".pocketmusic"
STATE_FILE = POCKET_DIR / "state.json"
BAR_PID_FILE = POCKET_DIR / "bar.pid"
SEARCH_TRIGGER = POCKET_DIR / "open-search"
MPV_SOCKET = POCKET_DIR / "mpv.sock"
SPOTLIGHT_CACHE = POCKET_DIR / "spotlight-tracks.json"
SPOTLIGHT_DOMAIN = "com.pocketmusic.tracks"
MPV_LOG = POCKET_DIR / "mpv.log"

# İndirme yok — sadece en iyi ses akışı (opus öncelikli)
AUDIO_FORMAT = "bestaudio[ext=opus]/bestaudio[acodec^=opus]/bestaudio/best"


@dataclass
class Track:
    id: str
    title: str
    uploader: str
    duration: int | None
    url: str
    thumbnail_url: str | None = None

    @property
    def duration_str(self) -> str:
        if self.duration is None:
            return "?:??"
        m, s = divmod(self.duration, 60)
        return f"{m}:{s:02d}"


@dataclass
class PlaybackState:
    title: str
    artist: str
    url: str
    thumbnail_path: str
    mpv_socket: str
    mpv_pid: int
    paused: bool = False


def ensure_dir() -> None:
    POCKET_DIR.mkdir(parents=True, exist_ok=True)


def request_search() -> None:
    ensure_dir()
    SEARCH_TRIGGER.touch()


def consume_search_request() -> bool:
    if SEARCH_TRIGGER.exists():
        SEARCH_TRIGGER.unlink(missing_ok=True)
        return True
    return False


def read_state() -> dict | None:
    if not STATE_FILE.exists():
        return None
    try:
        return json.loads(STATE_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def write_state(state: PlaybackState) -> None:
    ensure_dir()
    STATE_FILE.write_text(json.dumps(asdict(state), ensure_ascii=False, indent=2))


def clear_state() -> None:
    if STATE_FILE.exists():
        STATE_FILE.unlink()


def fetch_thumbnail_url(url: str) -> str | None:
    proc = subprocess.run(
        ["yt-dlp", "--no-warnings", "--quiet", "--print", "thumbnail", url],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    thumb = proc.stdout.strip()
    return thumb or None


def prepare_cover(video_id: str, thumbnail_url: str) -> str:
    ensure_dir()
    raw = POCKET_DIR / f"{video_id}_raw.jpg"
    icon = POCKET_DIR / f"{video_id}_icon.png"

    urllib.request.urlretrieve(thumbnail_url, raw)
    subprocess.run(
        ["sips", "-z", "22", "22", str(raw), "--out", str(icon)],
        check=False,
        capture_output=True,
    )
    if not icon.exists():
        # sips başarısız olursa ham dosyayı kullan
        return str(raw)
    return str(icon)


def mpv_ipc(command: list) -> dict | None:
    if not MPV_SOCKET.exists():
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(1.5)
            sock.connect(str(MPV_SOCKET))
            payload = json.dumps({"command": command}) + "\n"
            sock.sendall(payload.encode())
            data = sock.recv(8192).decode()
            if not data:
                return None
            return json.loads(data.split("\n")[0])
    except (OSError, json.JSONDecodeError):
        return None


def mpv_alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def stop_playback() -> None:
    mpv_ipc(["stop"])
    state = read_state()
    if state and mpv_alive(state.get("mpv_pid")):
        try:
            os.kill(state["mpv_pid"], 15)
        except OSError:
            pass
    if MPV_SOCKET.exists():
        MPV_SOCKET.unlink(missing_ok=True)
    clear_state()
    try:
        from mini_player import MiniPlayerController
        MiniPlayerController.shared().hide()
    except Exception:
        pass


def _mpv_path() -> str:
    return shutil.which("mpv") or "mpv"


def _wait_playing(pid: int, timeout: float = 15.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not mpv_alive(pid):
            return False
        if MPV_SOCKET.exists():
            resp = mpv_ipc(["get_property", "playback-state"])
            if resp and resp.get("data") in ("playing", "paused"):
                return True
        time.sleep(0.25)
    return False


def start_playback(track: Track) -> PlaybackState | None:
    ensure_dir()
    stop_playback()

    thumb_url = track.thumbnail_url or fetch_thumbnail_url(track.url)
    if not thumb_url:
        thumb_url = f"https://i.ytimg.com/vi/{track.id}/hqdefault.jpg"
    cover_path = prepare_cover(track.id, thumb_url)

    if MPV_SOCKET.exists():
        MPV_SOCKET.unlink(missing_ok=True)

    log_file = open(MPV_LOG, "a", encoding="utf-8")
    log_file.write(f"\n--- play {track.url} ---\n")
    log_file.flush()

    cmd = [
        _mpv_path(),
        "--no-video",
        f"--ytdl-format={AUDIO_FORMAT}",
        f"--input-ipc-server={MPV_SOCKET}",
        track.url,
    ]

    for attempt in range(2):
        if MPV_SOCKET.exists():
            MPV_SOCKET.unlink(missing_ok=True)

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=log_file,
            start_new_session=True,
        )

        if _wait_playing(proc.pid):
            state = PlaybackState(
                title=track.title,
                artist=track.uploader,
                url=track.url,
                thumbnail_path=cover_path,
                mpv_socket=str(MPV_SOCKET),
                mpv_pid=proc.pid,
                paused=False,
            )
            write_state(state)
            log_file.close()
            return state

        if mpv_alive(proc.pid):
            try:
                os.kill(proc.pid, 15)
            except OSError:
                pass
        time.sleep(0.5)

    log_file.close()
    return None


def ensure_bar_running() -> None:
    if BAR_PID_FILE.exists():
        try:
            pid = int(BAR_PID_FILE.read_text().strip())
            os.kill(pid, 0)
            return
        except (OSError, ValueError):
            BAR_PID_FILE.unlink(missing_ok=True)

    bar_script = Path(__file__).with_name("bar.py")
    python = sys.executable
    subprocess.Popen(
        [python, str(bar_script)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def is_paused() -> bool:
    resp = mpv_ipc(["get_property", "pause"])
    if resp and "data" in resp:
        return bool(resp["data"])
    state = read_state()
    return bool(state and state.get("paused"))


def toggle_pause() -> bool | None:
    resp = mpv_ipc(["cycle", "pause"])
    if resp is None:
        return None
    state = read_state()
    if state:
        paused = is_paused()
        state["paused"] = paused
        STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2))
        return paused
    return None


def search_tracks(query: str, limit: int = 10) -> list[Track]:
    proc = subprocess.run(
        [
            "yt-dlp",
            f"ytsearch{limit}:{query}",
            "--flat-playlist",
            "--dump-single-json",
            "--no-warnings",
            "--quiet",
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return []

    tracks: list[Track] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        data = json.loads(line)
        if data.get("_type") == "playlist":
            for entry in data.get("entries") or []:
                if entry:
                    tracks.append(_parse_track(entry))
        else:
            tracks.append(_parse_track(data))
    return tracks


def _parse_track(entry: dict) -> Track:
    vid = entry.get("id") or entry.get("url", "").split("=")[-1]
    thumb = entry.get("thumbnail")
    if not thumb:
        thumbs = entry.get("thumbnails") or []
        if thumbs:
            thumb = thumbs[-1].get("url")
    return Track(
        id=vid,
        title=entry.get("title") or "Bilinmeyen",
        uploader=entry.get("uploader") or entry.get("channel") or "?",
        duration=entry.get("duration"),
        url=f"https://www.youtube.com/watch?v={vid}",
        thumbnail_url=thumb,
    )


def track_by_id(video_id: str) -> Track | None:
    proc = subprocess.run(
        [
            "yt-dlp",
            "--no-warnings",
            "--quiet",
            "--dump-single-json",
            f"https://www.youtube.com/watch?v={video_id}",
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    data = json.loads(proc.stdout)
    return _parse_track(data)


def play_by_id(video_id: str) -> PlaybackState | None:
    track = track_by_id(video_id)
    if not track:
        return None
    ensure_bar_running()
    return start_playback(track)


def play_track(track: Track) -> PlaybackState | None:
    ensure_bar_running()
    return start_playback(track)


def play_query(query: str) -> PlaybackState | None:
    tracks = search_tracks(query.strip(), limit=1)
    if not tracks:
        return None
    ensure_bar_running()
    state = start_playback(tracks[0])
    if state:
        try:
            from spotlight import index_tracks
            index_tracks(tracks)
        except Exception:
            pass
    return state
