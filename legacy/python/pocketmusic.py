#!/bin/bash
case "${1:-}" in
  stop)
    pkill -x PocketMusic 2>/dev/null
    pkill mpv 2>/dev/null
    ;;
  *)
    open pocketmusic://search 2>/dev/null || open -a /Applications/PocketMusic.app
    ;;
esac
