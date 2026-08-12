"""macOS SF Symbol ikonları — menü için PNG."""

from __future__ import annotations

import AppKit

from common import POCKET_DIR, ensure_dir

ICON_DIR = POCKET_DIR / "icons"

_SYMBOLS = {
    "music": "music.note",
    "search": "magnifyingglass",
    "play": "play.fill",
    "pause": "pause.fill",
    "stop": "stop.fill",
    "power": "power",
}


def _render(symbol: str, path: str, size: float = 14) -> str:
    img = AppKit.NSImage.imageWithSystemSymbolName_accessibilityDescription_(symbol, symbol)
    if img is None:
        return ""
    config = AppKit.NSImageSymbolConfiguration.configurationWithPointSize_weight_(
        size, AppKit.NSFontWeightRegular
    )
    img = img.imageWithSymbolConfiguration_(config)
    img.setTemplate_(True)
    tiff = img.TIFFRepresentation()
    rep = AppKit.NSBitmapImageRep.imageRepWithData_(tiff)
    png = rep.representationUsingType_properties_(AppKit.NSPNGFileType, None)
    png.writeToFile_atomically_(path, True)
    return path


def icon(name: str) -> str | None:
    symbol = _SYMBOLS.get(name)
    if not symbol:
        return None
    ensure_dir()
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    path = str(ICON_DIR / f"{name}.png")
    if not (ICON_DIR / f"{name}.png").exists():
        _render(symbol, path)
    return path


def status_icon(name: str = "music") -> str | None:
    ensure_dir()
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    symbol = _SYMBOLS.get(name, "music.note")
    path = str(ICON_DIR / f"status_{name}.png")
    if not (ICON_DIR / f"status_{name}.png").exists():
        _render(symbol, path, size=18)
    return path
