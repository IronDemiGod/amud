#!/usr/bin/env bash
# Builds amdl and coverfix from the amdl fork (the submodule) for all platforms
# and publishes them as a GitHub release of THIS repo (amud), not of the fork.
# The tag is created on amud's current commit (which pins the fork's commit).
# Releases before v0.1.4.2 were on the fork; v0.1.4.1 was removed from there.
#
#   scripts/release.sh v0.1.4.3            publish
#   scripts/release.sh v0.1.4.3 --dry-run  build into ../amud-work/dist/release/ only
#
# It first checks zhaarey's upstream for commits the fork lacks and stops if
# there are any (a dry run only warns); ALLOW_BEHIND_UPSTREAM=1 releases anyway.
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

# Upstream check: commits on zhaarey's main that the fork does not have yet.
# Prints them; returns 1 when the fork is behind, 0 otherwise (also when
# upstream cannot be reached, after a warning).
upstream_behind() {
  git remote get-url upstream >/dev/null 2>&1 || { echo "[upstream] no 'upstream' remote; not checked"; return 0; }
  if ! timeout 20 git fetch -q upstream main 2>/dev/null; then
    echo "[upstream] could not reach upstream; not checked"; return 0
  fi
  local n; n="$(git rev-list --count HEAD..upstream/main)"
  [ "$n" -gt 0 ] || { echo "[upstream] up to date with upstream/main"; return 0; }
  echo "[upstream] WARNING: upstream/main has $n commit(s) the fork does not have:"
  git log --format='    %h %ad %s' --date=short -n 10 HEAD..upstream/main
  [ "$n" -le 10 ] || echo "    ..."
  echo "    merge them first: cd apple-music-downloader && git merge upstream/main"
  return 1
}

# Wrapper check: commits on WorldObservationLog/wrapper's lite branch that the
# wrapper submodule does not have. A warning only (the wrapper is not released).
wrapper_behind() {
  local w="$1"
  [ -d "$w/.git" ] || [ -f "$w/.git" ] || { echo "[wrapper] no wrapper submodule; not checked"; return 0; }
  if ! timeout 20 git -C "$w" fetch -q origin lite 2>/dev/null; then
    echo "[wrapper] could not reach the wrapper repo; not checked"; return 0
  fi
  local n; n="$(git -C "$w" rev-list --count HEAD..origin/lite)"
  [ "$n" -gt 0 ] || { echo "[wrapper] up to date with origin/lite"; return 0; }
  echo "[wrapper] NOTE: wrapper's lite branch has $n commit(s) the submodule does not have:"
  git -C "$w" log --format='    %h %ad %s' --date=short -n 10 HEAD..origin/lite
  [ "$n" -le 10 ] || echo "    ..."
  echo "    update: git -C $w merge --ff-only origin/lite, then rebuild (scripts/build-wrapper-win.sh)"
  return 1
}
wrapper_behind "$ROOT/wrapper" || true   # informational: the wrapper is not part of releases

if ! upstream_behind && [ -z "$DRY" ] && [ "${ALLOW_BEHIND_UPSTREAM:-}" != 1 ]; then
  echo "[release] stopped: the fork is behind upstream (ALLOW_BEHIND_UPSTREAM=1 releases anyway)"; exit 1
fi

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
# One zip per platform with both programs under plain names (amdl, coverfix;
# .exe on Windows), executable bits kept. The single files stay too: they are
# what `amdl --update` downloads.
(cd "$OUT" && python3 - <<'PY'
import os, stat, zipfile
for t in ["linux_amd64", "linux_arm64", "windows_amd64", "windows_arm64", "darwin_amd64", "darwin_arm64"]:
    ext = ".exe" if t.startswith("windows") else ""
    with zipfile.ZipFile(f"amdl-coverfix_{t}.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for tool in ("amdl", "coverfix"):
            zi = zipfile.ZipInfo.from_file(f"{tool}_{t}{ext}", arcname=tool + ext)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (stat.S_IFREG | 0o755) << 16
            with open(f"{tool}_{t}{ext}", "rb") as f:
                z.writestr(zi, f.read())
PY
)
(cd "$OUT" && sha256sum amdl_* coverfix_* amdl-coverfix_*.zip > checksums.txt)

BASE="$(git describe --tags --abbrev=0 "$(git merge-base HEAD upstream/main)" 2>/dev/null || echo upstream)"
cat > "$OUT/NOTES.md" <<NOTES
Builds of [this fork](https://github.com/$FORK) of zhaarey/apple-music-downloader, based on upstream **$BASE** (commit \`${SHA:0:7}\`).

**Install and setup guide:** https://github.com/$OWNER/amud#install

### Added in this fork
- \`paths.playlist-album-folders: true\`: playlist tracks go to their own \`Artist/Album/\` folders, like single-song downloads.
- Covers: \`artwork.format: "original"\` saves a full-size lossless PNG when Apple refuses the source image (currently always).
- \`coverfix\`: redo \`cover.*\` files and the pictures embedded in .flac / .m4a tracks of an existing library (\`coverfix --help\`).
- Windows: clearer errors when a save folder cannot be created.
- Faster: after each download, the next one starts right away; processing, tagging and conversion to FLAC run in the background.
- \`general.parallel-downloads\`: download several tracks at once (e.g. 3) on a fast connection.
- Live progress bars for albums and playlists, like coverfix: songs done and time left, plus a bar per track with quality, progress and speed (\`--no-live\` for plain output).
- Big playlists with \`playlist-album-folders\` start at once and keep all parallel downloads busy (next albums and covers fetched ahead).
- Running a playlist or album again is quick: already downloaded tracks are skipped in moments, and an album folder that has its cover keeps it (coverfix refreshes covers).
- \`convert.parallel\`: how many FLAC conversions run at once (0 = automatic).
- \`paths.work-dir\` (default \`auto\`: RAM on Linux, kept in memory on Windows): process tracks in a fast folder, then move only the finished file to the save folder.
- Interrupted runs no longer leave half-finished files that the next run skips (temporary \`.part\` names until a file is complete).
- Ctrl+C cleans up: the cursor comes back and the work folder is removed.
- Album covers download in the background, so a big \`original\` cover no longer holds up the album's tracks.
- \`--timings\`: shows how long each stage of a download takes.
- coverfix: several albums at once (\`--parallel\`), with live progress bars (\`--no-live\` for plain output), and \`--in FOLDER\` for a list of artist/album names inside one folder.
- \`amdl --update\` updates from [these releases](https://github.com/$SLUG/releases).

### Files
Easiest: download the zip for your computer; it holds both programs (\`amdl\` and \`coverfix\`, \`.exe\` on Windows).

| | zip (amdl + coverfix) |
|---|---|
| Windows x64 | \`amdl-coverfix_windows_amd64.zip\` |
| Windows ARM | \`amdl-coverfix_windows_arm64.zip\` |
| Linux x64 | \`amdl-coverfix_linux_amd64.zip\` |
| Linux ARM | \`amdl-coverfix_linux_arm64.zip\` |
| macOS Apple Silicon | \`amdl-coverfix_darwin_arm64.zip\` |
| macOS Intel | \`amdl-coverfix_darwin_amd64.zip\` |

The same programs as single files (these are what \`amdl --update\` uses):

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
  "$OUT"/amdl_* "$OUT"/coverfix_* "$OUT"/amdl-coverfix_*.zip "$OUT/checksums.txt"
echo "[release] published: https://github.com/$SLUG/releases/tag/$TAG"
