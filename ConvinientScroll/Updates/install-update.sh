#!/bin/sh
set -u

pid="$1"
staged="$2"
target="$3"
fallback="$4"
failure_file="$5"

open_cmd="${MT_UPDATE_OPEN:-/usr/bin/open}"
move_cmd="${MT_UPDATE_MOVE:-/bin/mv}"
timeout_seconds="${MT_UPDATE_TIMEOUT:-30}"

fail() {
    mkdir -p "$(dirname "$failure_file")"
    printf '%s\n' "$1" > "$failure_file"
}

launch() {
    if [ -e "$1" ]; then
        "$open_cmd" "$1"
    fi
}

ticks=$((timeout_seconds * 5))
while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -le 0 ]; then
        fail "The app didn't quit in time."
        exit 1
    fi
    ticks=$((ticks - 1))
    sleep 0.2
done

name="$(basename "$target" .app)"
backup="$(dirname "$target")/$name (previous version).app"
rm -rf "$backup"

had_backup=0
if [ -e "$target" ]; then
    if [ -e "$backup" ] || ! "$move_cmd" "$target" "$backup"; then
        fail "The old version couldn't be moved aside."
        launch "$fallback"
        exit 1
    fi
    had_backup=1
fi

if [ -e "$target" ] || ! "$move_cmd" "$staged" "$target"; then
    restored=1
    if [ "$had_backup" -eq 1 ]; then
        rm -rf "$target"
        if [ -e "$target" ] || ! "$move_cmd" "$backup" "$target"; then
            restored=0
        fi
    else
        rm -rf "$target"
    fi
    if [ "$restored" -eq 0 ]; then
        fail "The new version couldn't be moved to Applications, and the previous version couldn't be put back. It is kept in the Applications folder as $(basename "$backup")."
        if [ -e "$fallback" ]; then
            launch "$fallback"
        else
            launch "$backup"
        fi
        exit 1
    fi
    fail "The new version couldn't be moved to Applications."
    if [ "$had_backup" -eq 1 ]; then
        launch "$target"
    else
        launch "$fallback"
    fi
    exit 1
fi

rm -rf "$backup"
xattr -dr com.apple.quarantine "$target" 2>/dev/null
"$open_cmd" "$target"
exit 0
