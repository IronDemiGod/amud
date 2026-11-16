#!/usr/bin/env bash
# Copies the Windows builds from ../amud-work/dist/ to a Windows folder, e.g. one on a
# drive shared with Windows:  scripts/deploy-windows.sh /mnt/d/amud
# Never overwrites config.yaml or the wrapper's qemu/data.img, which holds the
# Apple login tokens.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Build outputs, downloads and the Linux run folder live outside the repo, in
# ../amud-work next to it (override with AMUD_WORK=/some/folder).
WORK="${AMUD_WORK:-$(dirname "$ROOT")/amud-work}"
DEST="${1:?usage: deploy-windows.sh <windows folder>}"
mkdir -p "$DEST/wrapper-lite/qemu"

cp "$WORK/dist/windows/amdl.exe" "$WORK/dist/windows/coverfix.exe" "$DEST/"
echo "[deploy] amdl.exe, coverfix.exe"

if [ -d "$WORK/dist/wrapper-lite-win" ]; then
  W="$WORK/dist/wrapper-lite-win"
  (cd "$W" && tar --exclude=./qemu/data.img -cf - .) | (cd "$DEST/wrapper-lite" && tar -xf -)
  if [ ! -f "$DEST/wrapper-lite/qemu/data.img" ]; then
    cp "$W/qemu/data.img" "$DEST/wrapper-lite/qemu/data.img"
    echo "[deploy] wrapper-lite (fresh data.img: run login.bat once)"
  else
    echo "[deploy] wrapper-lite (kept existing data.img with your login)"
  fi
fi
[ -f "$DEST/config.yaml" ] || cp "$ROOT/apple-music-downloader/config.yaml.example" "$DEST/config.yaml"
echo "[deploy] done: $DEST"
