#!/usr/bin/env bash
# Builds amdl and coverfix for Linux and Windows (amd64) into ../amud-work/dist/.
#   dist/linux/{amdl,coverfix}   dist/windows/{amdl.exe,coverfix.exe}
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Build outputs, downloads and the Linux run folder live outside the repo, in
# ../amud-work next to it (override with AMUD_WORK=/some/folder).
WORK="${AMUD_WORK:-$(dirname "$ROOT")/amud-work}"
SRC="$ROOT/apple-music-downloader"
cd "$SRC"
COMMIT="$(git rev-parse --short HEAD)"
# Bake in amud (this repo, where releases are published) as update source, so
# `amdl --update` on a local build installs amud's releases, not upstream's.
SLUG="$(git -C "$ROOT" remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"
LDFLAGS="-s -w -X 'amdl/internal/version.Commit=$COMMIT' \
-X 'amdl/internal/updater.RepoOwner=${SLUG%%/*}' -X 'amdl/internal/updater.RepoName=${SLUG##*/}'"
mkdir -p "$WORK/dist/linux" "$WORK/dist/windows"

echo "[amdl] testing..."
go test ./internal/... ./cmd/... >/dev/null

echo "[amdl] building linux..."
go build -trimpath -ldflags="$LDFLAGS" -o "$WORK/dist/linux/amdl" .
go build -trimpath -ldflags="-s -w" -o "$WORK/dist/linux/coverfix" ./cmd/coverfix

echo "[amdl] building windows..."
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="$LDFLAGS" -o "$WORK/dist/windows/amdl.exe" .
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o "$WORK/dist/windows/coverfix.exe" ./cmd/coverfix

# run/ is where amdl is used on Linux: config.yaml plus links to the builds.
mkdir -p "$WORK/run"
[ -f "$WORK/run/config.yaml" ] || cp "$SRC/config.yaml.example" "$WORK/run/config.yaml"
ln -sfn ../dist/linux/amdl "$WORK/run/amdl"
ln -sfn ../dist/linux/coverfix "$WORK/run/coverfix"

echo "[amdl] done (commit $COMMIT):"
ls -l "$WORK/dist/linux" "$WORK/dist/windows"
