#!/usr/bin/env bash
# Builds amdl and coverfix from the amdl fork (the submodule) for all platforms
# and publishes them as a GitHub release of THIS repo (amud), not of the fork.
# The tag is created on amud's current commit (which pins the fork's commit).
# Releases before v0.1.4.2 were on the fork; v0.1.4.1 was removed from there.
#
#   scripts/release.sh v0.1.4.3            publish
#   scripts/release.sh v0.1.4.3 --dry-run  build into ../amud-work/dist/release/ only
#
# Tag scheme: v<upstream version>.<fork revision>, e.g. v0.1.4.1, v0.1.4.2,
# then v0.1.5.1 after rebasing onto upstream v0.1.5. amdl's version check
# ignores "-suffixes", so the revision has to be a fourth number.
#
# The binaries have amud baked in as their update source, so `amdl --update`
# installs amud's releases rather than upstream's (the update source must be the
# repo the release is published on).
# The wrapper-lite package is deliberately not released: it contains Apple's
# proprietary libraries and GPL'd QEMU binaries. Build it with
# build-wrapper-win.sh instead.
set -euo pipefail
TAG="${1:?usage: release.sh <tag, e.g. v0.1.4.1> [--dry-run]}"
DRY="${2:-}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "tag must look like v0.1.4.1"; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Build outputs, downloads and the Linux run folder live outside the repo, in
# ../amud-work next to it (override with AMUD_WORK=/some/folder).
WORK="${AMUD_WORK:-$(dirname "$ROOT")/amud-work}"
SRC="$ROOT/apple-music-downloader"
cd "$SRC"
slug() { sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' <<<"$1"; }
FORK="$(slug "$(git remote get-url origin)")"            # where the source lives
SLUG="$(slug "$(git -C "$ROOT" remote get-url origin)")" # where releases go (amud)
OWNER="${SLUG%%/*}"; NAME="${SLUG##*/}"

if [ -z "$DRY" ]; then
  [ -z "$(git status --porcelain)" ] || { echo "amdl has uncommitted changes; commit them first"; exit 1; }
  git fetch -q origin
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "amdl HEAD is not origin/main; push first"; exit 1; }
  ! gh release view "$TAG" --repo "$SLUG" >/dev/null 2>&1 || { echo "release $TAG already exists"; exit 1; }
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || { echo "amud has uncommitted changes; commit them first"; exit 1; }
  git -C "$ROOT" fetch -q origin
  [ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse origin/main)" ] || { echo "amud HEAD is not origin/main; push first"; exit 1; }
  [ "$(git -C "$ROOT" ls-tree HEAD apple-music-downloader | awk '{print $3}')" = "$(git rev-parse HEAD)" ] \
    || { echo "amud's submodule pointer is not the fork's HEAD; commit and push amud first"; exit 1; }
fi

SHA="$(git rev-parse HEAD)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LDFLAGS="-s -w -X 'amdl/internal/version.Version=$TAG' -X 'amdl/internal/version.Commit=$SHA' \
-X 'amdl/internal/version.BuildDate=$DATE' -X 'amdl/internal/updater.RepoOwner=$OWNER' \
-X 'amdl/internal/updater.RepoName=$NAME'"

echo "[release] testing..."
go test ./internal/... ./cmd/... >/dev/null

OUT="$WORK/dist/release/$TAG"
rm -rf "$OUT" && mkdir -p "$OUT"
for target in linux/amd64 linux/arm64 windows/amd64 windows/arm64 darwin/amd64 darwin/arm64; do
  os="${target%/*}"; arch="${target#*/}"; ext=""
  [ "$os" = windows ] && ext=".exe"
  echo "[release] $os/$arch"
  CGO_ENABLED=0 GOOS=$os GOARCH=$arch go build -trimpath -ldflags="$LDFLAGS" -o "$OUT/amdl_${os}_${arch}${ext}" .
  CGO_ENABLED=0 GOOS=$os GOARCH=$arch go build -trimpath -ldflags="-s -w" -o "$OUT/coverfix_${os}_${arch}${ext}" ./cmd/coverfix
done
(cd "$OUT" && sha256sum amdl_* coverfix_* > checksums.txt)

BASE="$(git describe --tags --abbrev=0 "$(git merge-base HEAD upstream/main)" 2>/dev/null || echo upstream)"
cat > "$OUT/NOTES.md" <<NOTES
Builds of [this fork](https://github.com/$FORK) of zhaarey/apple-music-downloader, based on upstream **$BASE** (commit \`${SHA:0:7}\`).

**Install and setup guide:** https://github.com/$OWNER/amud#install

### Added in this fork
- \`paths.playlist-album-folders: true\`: playlist tracks go to their own \`Artist/Album/\` folders, like single-song downloads.
- Covers: \`artwork.format: "original"\` saves a full-size lossless PNG when Apple refuses the source image (currently always).
- \`coverfix\`: redo \`cover.*\` files and the pictures embedded in .flac / .m4a tracks of an existing library (\`coverfix --help\`).
- Windows: clearer errors when a save folder cannot be created.
- Faster: conversion to FLAC (\`convert.after-download\`) runs in the background while the next track downloads.
- \`--timings\`: shows how long each stage of a download takes.
- \`amdl --update\` updates from [these releases](https://github.com/$SLUG/releases).

### Files
| | amdl | coverfix |
|---|---|---|
| Windows x64 | \`amdl_windows_amd64.exe\` | \`coverfix_windows_amd64.exe\` |
| Windows ARM | \`amdl_windows_arm64.exe\` | \`coverfix_windows_arm64.exe\` |
| Linux x64 | \`amdl_linux_amd64\` | \`coverfix_linux_amd64\` |
| Linux ARM | \`amdl_linux_arm64\` | \`coverfix_linux_arm64\` |
| macOS Apple Silicon | \`amdl_darwin_arm64\` | \`coverfix_darwin_arm64\` |
| macOS Intel | \`amdl_darwin_amd64\` | \`coverfix_darwin_amd64\` |

Tested on Windows x64 and Linux x64; the other builds are cross-compiled and untested.
amdl needs [wrapper-lite](https://github.com/WorldObservationLog/wrapper/tree/lite) running; see the setup guide.
NOTES

ls -l "$OUT"
if [ -n "$DRY" ]; then echo "[release] dry run: nothing published"; exit 0; fi
gh release create "$TAG" --repo "$SLUG" --target "$(git -C "$ROOT" rev-parse HEAD)" --title "$TAG" --notes-file "$OUT/NOTES.md" \
  "$OUT"/amdl_* "$OUT"/coverfix_* "$OUT/checksums.txt"
echo "[release] published: https://github.com/$SLUG/releases/tag/$TAG"
