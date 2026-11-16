#!/usr/bin/env bash
# Builds amdl and coverfix for Linux and Windows (amd64) into dist/.
#   dist/linux/{amdl,coverfix}   dist/windows/{amdl.exe,coverfix.exe}
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apple-music-downloader"
cd "$SRC"
COMMIT="$(git rev-parse --short HEAD)"
LDFLAGS="-s -w -X 'amdl/internal/version.Commit=$COMMIT'"
mkdir -p "$ROOT/dist/linux" "$ROOT/dist/windows"

echo "[amdl] testing..."
go test ./internal/... ./cmd/... >/dev/null

echo "[amdl] building linux..."
go build -trimpath -ldflags="$LDFLAGS" -o "$ROOT/dist/linux/amdl" .
go build -trimpath -ldflags="-s -w" -o "$ROOT/dist/linux/coverfix" ./cmd/coverfix

echo "[amdl] building windows..."
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="$LDFLAGS" -o "$ROOT/dist/windows/amdl.exe" .
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o "$ROOT/dist/windows/coverfix.exe" ./cmd/coverfix

# run/ is where amdl is used on Linux: config.yaml plus links to the builds.
mkdir -p "$ROOT/run"
[ -f "$ROOT/run/config.yaml" ] || cp "$SRC/config.yaml.example" "$ROOT/run/config.yaml"
ln -sfn ../dist/linux/amdl "$ROOT/run/amdl"
ln -sfn ../dist/linux/coverfix "$ROOT/run/coverfix"

echo "[amdl] done (commit $COMMIT):"
ls -l "$ROOT/dist/linux" "$ROOT/dist/windows"
