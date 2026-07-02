#!/usr/bin/env bash
# Shared by run-gui.sh and grader/grade.sh: detect whether a real Wayland or
# X11 display is available and export the env vars / compose overlay file the
# GUI runtime containers need. Sets the globals VISUAL_RELAY_UID,
# VISUAL_RELAY_GID, VISUAL_RELAY_ENV (array of KEY=VALUE for the display
# backend) and VISUAL_RELAY_COMPOSE_FILES (array of `-f` compose args).
resolve_display_mode() {
    VISUAL_RELAY_UID="$(id -u)"
    VISUAL_RELAY_GID="$(id -g)"
    local host_name
    host_name="$(hostname)"

    if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
        VISUAL_RELAY_COMPOSE_FILES=(-f compose.yaml -f compose.gui-wayland.yaml)
        VISUAL_RELAY_ENV=(
            "VISUAL_RELAY_X11_HOSTNAME=$host_name"
            "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
            "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
        )
        return 0
    fi

    if [[ -n "${DISPLAY:-}" ]]; then
        local xauthority="${XAUTHORITY:-$HOME/.Xauthority}"
        if [[ ! -r "$xauthority" ]]; then
            printf 'X11 mode needs a readable Xauthority file. Set XAUTHORITY or run from a login desktop session.\n' >&2
            return 2
        fi
        VISUAL_RELAY_COMPOSE_FILES=(-f compose.yaml -f compose.gui-x11.yaml)
        VISUAL_RELAY_ENV=(
            "VISUAL_RELAY_X11_HOSTNAME=$host_name"
            "DISPLAY=$DISPLAY"
            "XAUTHORITY=$xauthority"
        )
        return 0
    fi

    printf 'No supported Linux display detected. Set WAYLAND_DISPLAY/XDG_RUNTIME_DIR or DISPLAY/XAUTHORITY.\n' >&2
    return 2
}
