#!/usr/bin/env bash
# Builds the native-Windows wrapper-lite package (QEMU launcher + guest VM)
# into dist/wrapper-lite-win/. Needs Docker; nothing is installed on the host.
#
# Steps: compile lite + guest kernel/initramfs/data.img and the Windows
# launcher in an Ubuntu 24.04 container, boot the guest once as a smoke test,
# then add QEMU for Windows (qemu.weilnetz.de, checksum-verified).
#
# Gotcha this script handles: the guest's /init starts with #!/bin/busybox,
# but Ubuntu 24.04's busybox-static installs to /usr/bin/busybox and the guest
# kernel-panics ("No working init found"). The Ubuntu 22.04 package, which
# upstream CI uses, is put in place instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/wrapper"
CACHE="$ROOT/.cache"
OUT="$ROOT/dist/wrapper-lite-win"
QEMU_VER="${QEMU_VER:-20260811}"   # see https://qemu.weilnetz.de/w64/
mkdir -p "$CACHE"

echo "[wrapper] getting busybox-static from Ubuntu 22.04..."
rm -f "$SRC"/busybox-static_*_amd64.deb
mkdir -p "$CACHE/busybox"
if ! ls "$CACHE"/busybox/busybox-static_*_amd64.deb >/dev/null 2>&1; then
  docker run --rm -v "$CACHE/busybox:/out" ubuntu:22.04 bash -c \
    'apt-get update -qq && cd /out && apt-get download busybox-static >/dev/null 2>&1 && chown '"$(id -u):$(id -g)"' /out/*'
fi
cp "$CACHE"/busybox/busybox-static_*_amd64.deb "$SRC/"

echo "[wrapper] building in container (first run downloads the Android NDK, ~1 GB)..."
cat > "$CACHE/in-container.sh" <<'IN'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential cmake unzip git aria2 ca-certificates \
  e2fsprogs cpio gzip zstd mingw-w64 linux-image-generic qemu-system-x86 curl >/dev/null
cd /src
KVER="$(ls /lib/modules | sort -V | tail -1)"
find /lib/modules/$KVER -name e1000.ko* | grep -q . || apt-get install -y -qq --no-install-recommends "linux-modules-extra-$KVER" >/dev/null
find /lib/modules/$KVER -name '*.ko.zst' -exec zstd -q -d --rm {} \;
[ -d android-ndk-r23b ] || { aria2c -q -o ndk.zip https://dl.google.com/android/repository/android-ndk-r23b-linux.zip && unzip -q ndk.zip && rm -f ndk.zip; }
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build -j"$(nproc)" >/dev/null
chmod +x qemu/*.sh
./qemu/mkdata.sh
printf '#!/bin/sh\nexec "$@"\n' > /usr/local/bin/sudo && chmod +x /usr/local/bin/sudo
KERNEL_SRC="/boot/vmlinuz-$KVER" ./qemu/build.sh
x86_64-w64-mingw32-g++ -std=c++11 -O2 -static -o wrapper-lite-qemu.exe wrapper-lite-qemu.cpp
g++ -std=c++11 -O2 -o wrapper-lite-qemu wrapper-lite-qemu.cpp
( ./wrapper-lite-qemu --accel tcg --qemu-bin "$(command -v qemu-system-x86_64)" --host-port 12399 > /tmp/smoke.log 2>&1 & )
ok=""
for _ in $(seq 1 120); do
  curl -fsS --max-time 2 http://127.0.0.1:12399/status >/dev/null 2>&1 && { ok=1; break; }
  grep -q "Kernel panic" /tmp/smoke.log && break
  sleep 1
done
pkill -f qemu-system-x86_64 || true
rm -f qemu/.lite-qemu-args
chown -R "$HOST_UID:$HOST_GID" /src
[ -n "$ok" ] || { echo "SMOKE TEST FAILED:"; tail -n 20 /tmp/smoke.log; exit 1; }
echo "[container] guest boots and answers /status"
IN
docker run --rm -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$SRC:/src" -v "$CACHE/in-container.sh:/in.sh:ro" ubuntu:24.04 bash /in.sh
# The container chmods the build scripts; undo that so the checkout stays clean.
git -C "$SRC" checkout -- qemu/build.sh qemu/mkdata.sh

echo "[wrapper] getting QEMU for Windows $QEMU_VER..."
INST="$CACHE/qemu-w64-setup-$QEMU_VER.exe"
if [ ! -f "$INST" ]; then
  curl -fsSL -o "$INST.tmp" "https://qemu.weilnetz.de/w64/qemu-w64-setup-$QEMU_VER.exe"
  curl -fsSL -o "$INST.sha512" "https://qemu.weilnetz.de/w64/qemu-w64-setup-$QEMU_VER.sha512"
  [ "$(sha512sum < "$INST.tmp" | cut -d' ' -f1)" = "$(cut -d' ' -f1 < "$INST.sha512")" ] || { echo "QEMU checksum mismatch"; exit 1; }
  mv "$INST.tmp" "$INST"
fi
rm -rf "$CACHE/qemu-win" && mkdir -p "$CACHE/qemu-win"
7z x -y -bso0 -bsp0 -o"$CACHE/qemu-win" "$INST"

echo "[wrapper] assembling $OUT..."
rm -rf "$OUT" && mkdir -p "$OUT/qemu/bin"
cp "$SRC/wrapper-lite-qemu.exe" "$SRC/README.md" "$SRC/LICENSE" "$OUT/"
cp "$SRC/qemu/vmlinuz-lite-qemu" "$SRC/qemu/lite-initramfs.cpio.gz" "$SRC/qemu/data.img" "$OUT/qemu/"
Q="$CACHE/qemu-win"
cp "$Q/qemu-system-x86_64.exe" "$Q"/*.dll "$Q/COPYING" "$Q/COPYING.LIB" "$OUT/qemu/bin/"
(cd "$Q/share" && tar --exclude=./doc --exclude=./icons --exclude=./applications \
  --exclude='./edk2-aarch64*' --exclude='./edk2-arm*' --exclude='./edk2-riscv*' --exclude='./edk2-loongarch*' -cf - .) \
  | (cd "$OUT/qemu/bin" && tar -xf -)
printf '%s\r\n' '@echo off' \
  'rem One-time Apple ID login. Tokens are cached in qemu\data.img, then it exits.' \
  'rem If your account has 2FA, type the code into this window when asked.' \
  'cd /d "%~dp0"' 'set /p AMUSER=Apple ID email: ' 'set /p AMPASS=Apple ID password: ' \
  'wrapper-lite-qemu.exe --login "%AMUSER%:%AMPASS%"' 'set AMPASS=' 'set AMUSER=' 'pause' > "$OUT/login.bat"
printf '%s\r\n' '@echo off' \
  'rem Starts wrapper-lite on http://127.0.0.1:12340. Keep this window open while amdl runs.' \
  'cd /d "%~dp0"' 'wrapper-lite-qemu.exe --smp 1 --memory 512' 'pause' > "$OUT/start-wrapper.bat"
echo "[wrapper] done: $(du -sh "$OUT" | cut -f1) in $OUT"
