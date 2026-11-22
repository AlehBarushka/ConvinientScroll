#!/usr/bin/env bash
# Measures how much the running MacToolkit costs while idle and appends one row to
# docs/resource-usage.md. Run it with the modules set up for the scenario being measured and
# leave the Mac alone for the duration: no clicks on the app's menus. The display is kept awake,
# and a run is discarded if the display still turned off or the Mac slept, since both pause the
# app's timers.
#
#   ./scripts/app-lock.sh run "<session>: <what>" -- ./scripts/measure-resources.sh -n "thermal on, menu closed" [-d 120]
set -euo pipefail

APP_NAME="MacToolkit"
DOMAIN="com.alehbarushka.convinientscroll"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HISTORY="$ROOT/docs/resource-usage.md"
DURATION=120
NOTE=""

usage() { echo "usage: $0 -n <scenario> [-d seconds]" >&2; exit 2; }
fail() { echo "error: $*" >&2; exit 1; }

while getopts "n:d:" opt; do
  case "$opt" in
    n) NOTE="${OPTARG//|//}" ;;
    d) DURATION="$OPTARG" ;;
    *) usage ;;
  esac
done
[[ -n "$NOTE" ]] || usage
[[ "$DURATION" =~ ^[1-9][0-9]*$ && "$DURATION" -ge 10 ]] || fail "duration must be at least 10 seconds"
[[ -n "${MACTOOLKIT_APP_LOCK:-}" && -d "$MACTOOLKIT_APP_LOCK" ]] \
  || fail "run it under scripts/app-lock.sh, or another session's xcodebuild test can quit the app mid-measurement"

PIDS=($(pgrep -x "$APP_NAME" || true))
[[ ${#PIDS[@]} -eq 1 ]] || fail "expected exactly one running $APP_NAME, found ${#PIDS[@]}"
PID="${PIDS[0]}"

BINARY="$(ps -o comm= -p "$PID")"
BUNDLE="${BINARY%/Contents/MacOS/*}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUNDLE/Contents/Info.plist")"
if [[ "$BUNDLE" == /Applications/* ]]; then
  KIND="installed"
elif [[ -e "$BUNDLE/Contents/MacOS/$APP_NAME.debug.dylib" ]]; then
  KIND="debug build"
else
  KIND="release build"
fi

if [[ "$KIND" == "installed" ]]; then
  COMMIT="release"
else
  COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
  [[ -z "$(git -C "$ROOT" status --porcelain -- ConvinientScroll ConvinientScroll.xcodeproj)" ]] || COMMIT="$COMMIT+dirty"
fi

module() {
  local value
  value="$(defaults read "$DOMAIN" "modules.$1.enabled" 2>/dev/null || echo "$2")"
  [[ "$value" == 1 ]] && echo "$1"
}
MODULES="$(printf '%s ' $(module autoScroll 1) $(module shelf 1) $(module memory 0) $(module thermal 0) $(module apps 1))"
MODULES="${MODULES% }"

MAC="$(sysctl -n hw.model), $(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion)"

cpu_seconds() {
  ps -o time= -p "$PID" | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'
}

echo "Measuring $APP_NAME $VERSION ($KIND, pid $PID) for $DURATION s: $NOTE"
SAMPLES="$(mktemp)"
trap 'rm -f "$SAMPLES" "$SAMPLES.pmset"' EXIT

caffeinate -d -i -w $$ &
WINDOW_START="$(date '+%Y-%m-%d %H:%M:%S')"
CPU_START="$(cpu_seconds)"
top -l $((DURATION + 1)) -s 1 -pid "$PID" -stats pid,idlew,power \
  | awk -v pid="$PID" '$1 == pid { gsub(/\+/, ""); print $2, $3 }' > "$SAMPLES"
kill -0 "$PID" 2>/dev/null || fail "$APP_NAME exited during the measurement"
CPU_END="$(cpu_seconds)"
WINDOW_END="$(date '+%Y-%m-%d %H:%M:%S')"
pmset -g log > "$SAMPLES.pmset"
PAUSED="$(awk -v from="$WINDOW_START" -v to="$WINDOW_END" '
  /Display is turned off|Entering Sleep|^[0-9-]+ [0-9:]+ [+-][0-9]+ Sleep[[:space:]]/ {
    t = $1 " " $2; if (t >= from && t <= to && found == "") found = t }
  END { print found }' "$SAMPLES.pmset")"
[[ -z "$PAUSED" ]] || fail "the display turned off or the Mac slept at $PAUSED; the timers were paused, run it again"

read -r WAKEUPS POWER < <(awk -v d="$DURATION" '
  NR == 1 { first = $1; next }
  { last = $1; power += $2; n++ }
  END { printf "%.2f %.2f\n", (last - first) / d, power / n }' "$SAMPLES")
CPU_MS_PER_MIN="$(awk -v a="$CPU_START" -v b="$CPU_END" -v d="$DURATION" 'BEGIN { printf "%.0f", (b - a) * 1000 * 60 / d }')"
CPU_PERCENT="$(awk -v a="$CPU_START" -v b="$CPU_END" -v d="$DURATION" 'BEGIN { printf "%.3f", (b - a) * 100 / d }')"
FOOTPRINT="$(footprint -p "$PID" 2>/dev/null | awk '/Footprint:/ {
  for (i = 1; i <= NF; i++) if ($i == "Footprint:") { v = $(i + 1); u = $(i + 2) }
  if (u == "KB") v /= 1024; else if (u == "GB") v *= 1024
  printf "%.1f", v; exit }')"

if [[ ! -f "$HISTORY" ]]; then
  cat > "$HISTORY" <<'EOF'
# Потребление ресурсов

Строки добавляет `scripts/measure-resources.sh`; когда мерить, сказано в `CLAUDE.md` («Замер ресурсов»).
CPU — процессорное время процесса за окно замера; пробуждения — idle wakeups в секунду; Energy — среднее
`POWER` из `top` (то же, что «Energy Impact» в Activity Monitor); память — `footprint`.

| Дата | Версия | Сборка | Коммит | Модули | Сценарий | Окно, с | CPU, % | CPU, мс/мин | Пробуждения/с | Energy | Память, МБ | Mac |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
EOF
fi

ROW="| $(date +%Y-%m-%d) | $VERSION ($BUILD_NUMBER) | $KIND | $COMMIT | $MODULES | $NOTE | $DURATION | $CPU_PERCENT | $CPU_MS_PER_MIN | $WAKEUPS | $POWER | ${FOOTPRINT:-?} | $MAC |"
echo "$ROW" >> "$HISTORY"
echo "$ROW"
