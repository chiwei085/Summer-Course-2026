#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

case "${1:-}" in
    udp-loss)
        docker compose --profile runtime pause scout-station
        sleep "${2:-2}"
        docker compose --profile runtime unpause scout-station
        ;;
    tcp-handoff-cut)
        docker compose --profile runtime restart catcher-station
        ;;
    scout-restart)
        docker compose --profile runtime restart scout-station
        ;;
    catcher-restart)
        docker compose --profile runtime restart catcher-station
        ;;
    simulator-restart)
        docker compose --profile runtime restart relay-simulator
        ;;
    *)
        cat >&2 <<'USAGE'
usage: scripts/inject-network-fault.sh FAULT [SECONDS]

FAULT:
  udp-loss
  tcp-handoff-cut
  scout-restart
  catcher-restart
  simulator-restart
USAGE
        exit 2
        ;;
esac
