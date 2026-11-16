#!/usr/bin/env bash
# Native wrapper-lite on Linux: no Docker, no VM, no root. It runs wrapper's
# rootless launcher, which starts the Android "lite" service in an
# unprivileged user namespace (needs unprivileged user namespaces, on by
# default on most distributions).
#
# Install, from this repo:
#   scripts/wrapper-linux.sh install ~/amdl --from ~/Downloads/wrapper-lite-linux-x86_64
#       from wrapper's ready-made native package (unzipped), or
#   scripts/wrapper-linux.sh install ~/amdl
#       from the wrapper submodule, after scripts/build-wrapper-win.sh built it.
# Either installs into ~/amdl/wrapper-lite and copies this script to ~/amdl/wrapper.
# Then, from the install folder:
#   ./wrapper login     one-time: Apple ID, password (hidden) and 2FA code
#   ./wrapper start     start in the background (default command)
#   ./wrapper stop      stop it
#   ./wrapper status    running or not, and what /status answers
#   ./wrapper log       follow the log
#
# The service listens on 127.0.0.1:12340 (WRAPPER_PORT changes the port), which
# is amdl's default lite-server. The login (tokens) is kept in
# wrapper-lite/rootfs/data, readable only by you. Re-running install updates the
# program files and never touches that login.
set -euo pipefail
umask 077

PORT="${WRAPPER_PORT:-12340}"
HOST=127.0.0.1

install_to() {
  local dest="${1:?usage: wrapper-linux.sh install <folder> [--from <package folder>]}"
  local src
  src="$(cd "$(dirname "$0")/.." && pwd)/wrapper"
  if [ "${2:-}" = "--from" ]; then
    src="$(cd "${3:?--from needs the unzipped wrapper-lite-linux-x86_64 folder}" && pwd)"
  fi
  for f in "$src/wrapper-lite-rootless" "$src/rootfs/system/bin/lite" "$src/rootfs/system/bin/linker64"; do
    [ -e "$f" ] || { echo "missing $f: use --from with the unzipped wrapper-lite-linux-x86_64 package, or build with scripts/build-wrapper-win.sh"; exit 1; }
  done
  local w="$dest/wrapper-lite"
  mkdir -p "$w/rootfs/data"
  chmod 700 "$w" "$w/rootfs/data"
  install -m 755 "$src/wrapper-lite-rootless" "$w/wrapper-lite-rootless"
  rm -rf "$w/rootfs/system"
  cp -R "$src/rootfs/system" "$w/rootfs/system"
  # Downloaded artifacts lose the executable bits.
  chmod 755 "$w/rootfs/system/bin/lite" "$w/rootfs/system/bin/linker64"
  cp "$src/LICENSE" "$w/LICENSE"
  # Copy this script, unless it is that copy already (re-install from it).
  [ "$(readlink -f "$0")" = "$(readlink -f "$dest/wrapper" 2>/dev/null)" ] || install -m 755 "$0" "$dest/wrapper"
  echo "installed in $w (login data kept)"
  echo "next: $dest/wrapper login, then $dest/wrapper start"
}

# Everything below runs from an installed copy: <folder>/wrapper.
W="$(cd "$(dirname "$0")" && pwd)/wrapper-lite"
PIDFILE="$W/wrapper.pid"
LOG="$W/wrapper.log"

need_install() {
  [ -x "$W/wrapper-lite-rootless" ] || { echo "no wrapper-lite next to this script; install it first (see the top of this file)"; exit 1; }
}

running_pid() {
  [ -f "$PIDFILE" ] || return 1
  local pid
  pid="$(cat "$PIDFILE")"
  # The command line, not the name: right after start it may still be setsid/nohup.
  kill -0 "$pid" 2>/dev/null && tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q 'wrapper-lite-rootless' || return 1
  echo "$pid"
}

answer() {
  curl -s --max-time 2 "http://$HOST:$PORT/status" 2>/dev/null
}

logged_in() {
  [ -s "$W/rootfs/data/MUSIC_TOKEN" ] || ls "$W"/rootfs/data/*TOKEN* >/dev/null 2>&1
}

cmd_login() {
  need_install
  if running_pid >/dev/null; then cmd_stop; fi
  local user pass
  read -r -p "Apple ID: " user
  read -r -s -p "Password: " pass
  echo
  echo "Logging in (enter the 2FA code when asked)..."
  # lite only takes the login on its command line; it is visible to other
  # processes of this computer only while this one-off login runs.
  (cd "$W" && ./wrapper-lite-rootless --login "$user:$pass" --host "$HOST" --port "$PORT")
  unset pass
  chmod -R go-rwx "$W/rootfs/data"
  echo "Login saved. Start the service with: $0 start"
}

cmd_start() {
  need_install
  if pid="$(running_pid)"; then
    echo "already running (pid $pid) on $HOST:$PORT"
    return 0
  fi
  if answer >/dev/null; then
    echo "something else already answers on $HOST:$PORT; not starting a second wrapper"
    return 1
  fi
  logged_in || echo "warning: no saved login found; run: $0 login"
  # cd first, then background only the launcher, so $! is its PID (setsid and
  # nohup exec into it).
  (
    cd "$W" || exit 1
    setsid nohup ./wrapper-lite-rootless --host "$HOST" --port "$PORT" >>"$LOG" 2>&1 </dev/null &
    echo $! >"$PIDFILE"
  )
  for _ in $(seq 1 60); do
    if answer >/dev/null; then
      echo "started (pid $(cat "$PIDFILE")) on $HOST:$PORT; log: $LOG"
      return 0
    fi
    if ! running_pid >/dev/null; then
      echo "wrapper-lite exited; last log lines:"
      tail -n 20 "$LOG"
      return 1
    fi
    sleep 0.5
  done
  echo "started (pid $(cat "$PIDFILE")) but not answering yet; see $LOG"
}

cmd_stop() {
  local pid
  if ! pid="$(running_pid)"; then
    echo "not running"
    rm -f "$PIDFILE"
    return 0
  fi
  kill -INT "$pid" 2>/dev/null || true   # the launcher stops the service and exits
  for _ in $(seq 1 20); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  kill -0 "$pid" 2>/dev/null && kill -TERM -- "-$pid" 2>/dev/null || true
  rm -f "$PIDFILE"
  echo "stopped"
}

cmd_status() {
  local pid
  if pid="$(running_pid)"; then
    echo "running (pid $pid) on $HOST:$PORT"
    answer && echo
  else
    echo "not running"
    return 1
  fi
}

case "${1:-start}" in
  install) shift; install_to "$@" ;;
  login) cmd_login ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  restart) cmd_stop; cmd_start ;;
  status) cmd_status ;;
  log) tail -n 50 -f "$LOG" ;;
  *) echo "usage: $0 [install <folder>|login|start|stop|restart|status|log]"; exit 2 ;;
esac
