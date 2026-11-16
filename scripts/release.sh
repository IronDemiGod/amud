#!/usr/bin/env bash
# Builds amdl and coverfix for all platforms and publishes them as a GitHub
# release on the amdl fork (the submodule's origin).
#
#   scripts/release.sh v0.1.4.1            publish
#   scripts/release.sh v0.1.4.1 --dry-run  build into dist/release/ only
#
# Tag scheme: v<upstream version>.<fork revision>, e.g. v0.1.4.1, v0.1.4.2,
# then v0.1.5.1 after rebasing onto upstream v0.1.5. amdl's version check
# ignores "-suffixes", so the revision has to be a fourth number.
#
# The binaries have this fork baked in as their update source, so
# `amdl --update` installs the fork's releases rather than upstream's.
# The wrapper-lite package is deliberately not released: it contains Apple's
# proprietary libraries and GPL'd QEMU binaries. Build it with
# build-wrapper-win.sh instead.
set -euo pipefail
TAG="${1:?usage: release.sh <tag, e.g. v0.1.4.1> [--dry-run]}"
DRY="${2:-}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "tag must look like v0.1.4.1"; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apple-music-downloader"
cd "$SRC"
ORIGIN="$(git remote get-url origin)"
SLUG="$(sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' <<<"$ORIGIN")"
OWNER="${SLUG%%/*}"; NAME="${SLUG##*/}"

if [ -z "$DRY" ]; then
  [ -z "$(git status --porcelain)" ] || { echo "amdl has uncommitted changes; commit them first"; exit 1; }
  git fetch -q origin
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "amdl HEAD is not origin/main; push first"; exit 1; }
  ! gh release view "$TAG" --repo "$SLUG" >/dev/null 2>&1 || { echo "release $TAG already exists"; exit 1; }
fi

SHA="$(git rev-parse HEAD)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LDFLAGS="-s -w -X 'amdl/internal/version.Version=$TAG' -X 'amdl/internal/version.Commit=$SHA' \
-X 'amdl/internal/version.BuildDate=$DATE' -X 'amdl/internal/updater.RepoOwner=$OWNER' \
-X 'amdl/internal/updater.RepoName=$NAME'"

echo "[release] testing..."
go test ./internal/... ./cmd/... >/dev/null

OUT="$ROOT/dist/release/$TAG"
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
Builds of [this fork](https://github.com/$SLUG) of zhaarey/apple-music-downloader, based on upstream **$BASE** (commit \`${SHA:0:7}\`).

**Install and setup guide:** https://github.com/$OWNER/amud#install

### Added in this fork
- \`paths.playlist-album-folders: true\`: playlist tracks go to their own \`Artist/Album/\` folders, like single-song downloads.
- Covers: \`artwork.format: "original"\` saves a full-size lossless PNG when Apple refuses the source image (currently always).
- \`coverfix\`: redo \`cover.*\` files and the pictures embedded in .flac / .m4a tracks of an existing library (\`coverfix --help\`).
- Windows: clearer errors when a save folder cannot be created.
- \`amdl --update\` updates from this fork's releases.

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
gh release create "$TAG" --repo "$SLUG" --target "$SHA" --title "$TAG" --notes-file "$OUT/NOTES.md" \
  "$OUT"/amdl_* "$OUT"/coverfix_* "$OUT/checksums.txt"
echo "[release] published: https://github.com/$SLUG/releases/tag/$TAG"
