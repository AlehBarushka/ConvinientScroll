#!/usr/bin/env bash
# One lock for everything that starts, quits or replaces the running MacToolkit: `xcodebuild test`
# (it quits the running copy), launching a build of your own, resource measurements, swapping the
# installed copy. The lock lives in the git directory shared by every worktree of this repository.
#
#   ./scripts/app-lock.sh run [--no-wait] "<session>: <what>" -- <command> [args...]
#   ./scripts/app-lock.sh status
#
# `run` waits for the lock, holds it for the whole command and releases it on exit, Ctrl-C or
# TERM. With --no-wait it exits with 75 at once when the lock is taken. If /Applications/MacToolkit.app
# was running before the command and no MacToolkit runs after it, `run` starts the installed copy
# again. Settings changed by the command are not restored: whoever changed them puts them back.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd)"
LOCK="$COMMON/mactoolkit-app.lock"
INSTALLED="/Applications/MacToolkit.app"
BUSY=75

usage() {
  echo "usage: $0 run [--no-wait] \"<session>: <what>\" -- <command> [args...]" >&2
  echo "       $0 status" >&2
  exit 2
}

field() { sed -n "s/^$1=//p" "$LOCK/info" 2>/dev/null; }

holder() {
  local started now
  started="$(field started)"
  now="$(date +%s)"
  echo "$(field owner) (pid $(field pid), for $(( (now - ${started:-$now}) / 60 )) min)"
}

# A holder is gone when its pid is dead or now belongs to a process started at another time.
holder_alive() {
  local pid lstart
  pid="$(field pid)"
  if [[ -z "$pid" ]]; then
    # mkdir happened, info not written yet; give the holder a few seconds before calling it stale.
    local age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    [[ $age -lt 10 ]]
    return
  fi
  lstart="$(ps -o lstart= -p "$pid" 2>/dev/null || true)"
  [[ -n "$lstart" && "$lstart" == "$(field lstart)" ]]
}

acquire() {
  local owner="$1" wait="$2" last_report=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    if ! holder_alive; then
      echo "app-lock: removing the stale lock of $(holder)" >&2
      rm -rf "$LOCK"
      continue
    fi
    if [[ "$wait" == no ]]; then
      echo "app-lock: busy: $(holder)" >&2
      exit $BUSY
    fi
    if (( $(date +%s) - last_report >= 30 )); then
      echo "app-lock: waiting for $(holder)" >&2
      last_report="$(date +%s)"
    fi
    sleep 2
  done
  printf 'owner=%s\npid=%s\nlstart=%s\nstarted=%s\n' \
    "$owner" "$$" "$(ps -o lstart= -p $$)" "$(date +%s)" > "$LOCK/info"
}

installed_running() {
  pgrep -f "^$INSTALLED/Contents/MacOS/MacToolkit" >/dev/null
}

run() {
  local wait=yes
  [[ "${1:-}" == --no-wait ]] && { wait=no; shift; }
  local owner="${1:-}"
  [[ -n "$owner" && "${2:-}" == -- && $# -ge 3 ]] || usage
  shift 2

  acquire "$owner" "$wait"
  local child="" restore=no
  installed_running && restore=yes
  release() {
    trap - EXIT INT TERM
    [[ -n "$child" ]] && kill "$child" 2>/dev/null || true
    if [[ "$restore" == yes ]] && ! pgrep -x MacToolkit >/dev/null; then
      echo "app-lock: starting $INSTALLED again" >&2
      open "$INSTALLED" || true
    fi
    rm -rf "$LOCK"
  }
  trap 'release; exit 130' INT
  trap 'release; exit 143' TERM
  trap release EXIT

  export MACTOOLKIT_APP_LOCK="$LOCK"
  "$@" &
  child=$!
  local status=0
  wait "$child" || status=$?
  child=""
  exit "$status"
}

case "${1:-}" in
  run) shift; run "$@" ;;
  status)
    if [[ -d "$LOCK" ]] && holder_alive; then
      echo "busy: $(holder)"
      exit $BUSY
    fi
    echo "free"
    ;;
  *) usage ;;
esac
