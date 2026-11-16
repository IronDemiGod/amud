#!/usr/bin/env bash
# Copies the Windows builds from ../amud-work/dist/ to a Windows folder, e.g. one on a
# drive shared with Windows:
#   scripts/deploy-windows.sh /mnt/d/amud           newest release build (dist/release/)
#   scripts/deploy-windows.sh /mnt/d/amud --local   local build (dist/windows/)
# Release builds are the default: only they carry a version number, which
# `amdl --update` needs to tell whether a newer release exists. A local build
# reports "dev", so its --update always reinstalls the latest release.
# Never overwrites config.yaml or the wrapper's qemu/data.img, which holds the
# Apple login tokens.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Build outputs, downloads and the Linux run folder live outside the repo, in
# ../amud-work next to it (override with AMUD_WORK=/some/folder).
WORK="${AMUD_WORK:-$(dirname "$ROOT")/amud-work}"
DEST="${1:?usage: deploy-windows.sh <windows folder> [--local]}"
MODE="${2:-}"

if [ "$MODE" = --local ]; then
  AMDL="$WORK/dist/windows/amdl.exe"; COVERFIX="$WORK/dist/windows/coverfix.exe"; FROM="local build"
elif [ -z "$MODE" ]; then
  REL="$(ls -d "$WORK"/dist/release/v*/ 2>/dev/null | sort -V | tail -1)"
  [ -n "$REL" ] || { echo "no release build in $WORK/dist/release/: run release.sh (or --dry-run), or pass --local"; exit 1; }
  AMDL="$REL/amdl_windows_amd64.exe"; COVERFIX="$REL/coverfix_windows_amd64.exe"; FROM="release $(basename "$REL")"
else
  echo "unknown option: $MODE"; exit 2
fi
[ -f "$AMDL" ] && [ -f "$COVERFIX" ] || { echo "missing build: $AMDL / $COVERFIX"; exit 1; }

mkdir -p "$DEST/wrapper-lite/qemu"
cp "$AMDL" "$DEST/amdl.exe"
cp "$COVERFIX" "$DEST/coverfix.exe"
echo "[deploy] amdl.exe, coverfix.exe ($FROM)"

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
