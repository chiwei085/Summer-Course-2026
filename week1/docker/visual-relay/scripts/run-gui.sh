#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

uid="$(id -u)"
gid="$(id -g)"
host_name="$(hostname)"

if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
    exec env UID="$uid" GID="$gid" VISUAL_RELAY_X11_HOSTNAME="$host_name" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        docker compose --profile runtime -f compose.yaml -f compose.gui-wayland.yaml up --build
fi

if [[ -n "${DISPLAY:-}" ]]; then
    xauthority="${XAUTHORITY:-$HOME/.Xauthority}"
    if [[ ! -r "$xauthority" ]]; then
        printf 'X11 mode needs a readable Xauthority file. Set XAUTHORITY or run from a login desktop session.\n' >&2
        exit 2
    fi
    exec env UID="$uid" GID="$gid" VISUAL_RELAY_X11_HOSTNAME="$host_name" DISPLAY="$DISPLAY" XAUTHORITY="$xauthority" \
        docker compose --profile runtime -f compose.yaml -f compose.gui-x11.yaml up --build
fi

printf 'No supported Linux display detected. Set WAYLAND_DISPLAY/XDG_RUNTIME_DIR or DISPLAY/XAUTHORITY.\n' >&2
exit 2
