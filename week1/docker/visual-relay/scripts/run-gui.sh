#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib-display.sh

resolve_display_mode

exec env UID="$VISUAL_RELAY_UID" GID="$VISUAL_RELAY_GID" "${VISUAL_RELAY_ENV[@]}" \
    docker compose "${VISUAL_RELAY_COMPOSE_FILES[@]}" --profile runtime up --build
