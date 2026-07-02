#!/usr/bin/env bash
# Single entry point for grading the Visual Relay containerization
# assignment. Runs every check the assignment cares about and prints one
# scored report: static Dockerfile/compose design, containerized build +
# unit tests, runtime image hygiene, real GUI runtime health, and automated
# fault-recovery scenarios. Requires a real Wayland or X11 display (the same
# one `scripts/run-gui.sh` uses) because phases 4 and 5 start the actual GUI
# containers.
set -uo pipefail

cd "$(dirname "$0")/.."
source scripts/lib-display.sh

TEST_IMAGE="visual-relay/test:reference"
SIMULATOR_IMAGE="visual-relay/simulator:reference"
SCOUT_IMAGE="visual-relay/scout:reference"
CATCHER_IMAGE="visual-relay/catcher:reference"

PASS_COUNT=0
TOTAL_COUNT=0
declare -A PHASE_PASS
declare -A PHASE_TOTAL

record() {
    local phase="$1" name="$2" ok="$3"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    PHASE_TOTAL[$phase]=$(( ${PHASE_TOTAL[$phase]:-0} + 1 ))
    if [[ "$ok" == "0" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        PHASE_PASS[$phase]=$(( ${PHASE_PASS[$phase]:-0} + 1 ))
        echo "[PASS] $phase: $name"
    else
        echo "[FAIL] $phase: $name"
    fi
}

record_group() {
    # Adds `pass`/`total` counts straight into a phase without a single
    # PASS/FAIL line (used for the static-check sub-report, which already
    # printed its own per-rule PASS/FAIL lines).
    local phase="$1" pass="$2" total="$3"
    PASS_COUNT=$((PASS_COUNT + pass))
    TOTAL_COUNT=$((TOTAL_COUNT + total))
    PHASE_PASS[$phase]=$(( ${PHASE_PASS[$phase]:-0} + pass ))
    PHASE_TOTAL[$phase]=$(( ${PHASE_TOTAL[$phase]:-0} + total ))
}

wait_healthy() {
    local service="$1" timeout="${2:-60}" waited=0 cid status
    while (( waited < timeout )); do
        cid="$(dc ps -q "$service" 2>/dev/null || true)"
        if [[ -n "$cid" ]]; then
            status="$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "")"
            [[ "$status" == "healthy" ]] && return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

echo "== Phase 1/5: static Dockerfile/compose design =="
static_log="$(mktemp)"
python3 grader/check_static.py | tee "$static_log"
read -r static_pass static_total <<<"$(awk '/^STATIC_SCORE/ {print $2, $3}' "$static_log")"
rm -f "$static_log"
record_group static "${static_pass:-0}" "${static_total:-1}"

echo
echo "== Phase 2/5: containerized build + protocol/scene unit tests =="
if docker build --target test -t "$TEST_IMAGE" .; then
    record build "docker build --target test (ctest runs as part of the build)" 0
else
    record build "docker build --target test (ctest runs as part of the build)" 1
fi

echo
echo "== Phase 3/5: runtime image hygiene =="
check_runtime_image() {
    local name="$1" image="$2"
    docker run --rm --entrypoint sh "$image" -c '
        for tool in g++ cmake ninja git make python3; do
            if command -v "$tool" >/dev/null 2>&1; then
                echo "unexpected runtime tool: $tool" >&2
                exit 1
            fi
        done
        test -z "$(find /opt/visual-relay -name "*.cpp" -o -name CMakeCache.txt | head -n 1)"
    ' >/dev/null 2>&1
}

for entry in "simulator:$SIMULATOR_IMAGE" "scout:$SCOUT_IMAGE" "catcher:$CATCHER_IMAGE"; do
    name="${entry%%:*}"
    image="${entry#*:}"
    if docker build --target "${name}-runtime" -t "$image" . >/dev/null 2>&1; then
        record image "$name runtime image builds" 0
        if check_runtime_image "$name" "$image"; then
            record image "$name runtime image has no build tools or sources" 0
        else
            record image "$name runtime image has no build tools or sources" 1
        fi
    else
        record image "$name runtime image builds" 1
        record image "$name runtime image has no build tools or sources" 1
    fi
done

echo
echo "== Phase 4/5: runtime health (real GUI containers) =="
DISPLAY_OK=1
if ! resolve_display_mode; then
    DISPLAY_OK=0
fi

if [[ "$DISPLAY_OK" == "1" ]]; then
    dc() {
        env UID="$VISUAL_RELAY_UID" GID="$VISUAL_RELAY_GID" "${VISUAL_RELAY_ENV[@]}" \
            docker compose "${VISUAL_RELAY_COMPOSE_FILES[@]}" --profile runtime "$@"
    }
    cleanup() { dc down --remove-orphans >/dev/null 2>&1 || true; }
    trap cleanup EXIT

    dc up --build -d >/dev/null 2>&1
    for service in relay-simulator scout-station catcher-station; do
        if wait_healthy "$service" 60; then
            record runtime "$service becomes healthy" 0
        else
            record runtime "$service becomes healthy" 1
        fi
    done
else
    record runtime "real Wayland or X11 display detected" 1
    record runtime "relay-simulator becomes healthy" 1
    record runtime "scout-station becomes healthy" 1
    record runtime "catcher-station becomes healthy" 1
fi

echo
echo "== Phase 5/5: automated fault-recovery scenarios =="
run_fault() {
    local label="$1" action="$2" timeout="$3"
    shift 3
    local services=("$@") ok=0
    eval "$action"
    for service in "${services[@]}"; do
        wait_healthy "$service" "$timeout" || ok=1
    done
    record fault "$label" "$ok"
}

if [[ "$DISPLAY_OK" == "1" ]]; then
    run_fault "udp-loss: scout tolerates a brief pause" \
        'dc pause scout-station; sleep 2; dc unpause scout-station' 30 scout-station
    run_fault "tcp-handoff-cut: catcher reconnects after restart" \
        'dc restart catcher-station' 60 catcher-station
    run_fault "scout-restart: scout recovers" \
        'dc restart scout-station' 60 scout-station
    run_fault "catcher-restart: catcher recovers" \
        'dc restart catcher-station' 60 catcher-station
    run_fault "simulator-restart: whole system recovers" \
        'dc restart relay-simulator' 90 relay-simulator scout-station catcher-station
else
    record fault "udp-loss: scout tolerates a brief pause" 1
    record fault "tcp-handoff-cut: catcher reconnects after restart" 1
    record fault "scout-restart: scout recovers" 1
    record fault "catcher-restart: catcher recovers" 1
    record fault "simulator-restart: whole system recovers" 1
fi

echo
echo "===================================================="
echo "RESULTS BY PHASE"
for phase in static build image runtime fault; do
    p=${PHASE_PASS[$phase]:-0}
    t=${PHASE_TOTAL[$phase]:-0}
    printf '  %-8s %d/%d\n' "$phase" "$p" "$t"
done
printf 'TOTAL SCORE: %d/%d\n' "$PASS_COUNT" "$TOTAL_COUNT"

if [[ "$PASS_COUNT" -eq "$TOTAL_COUNT" ]]; then
    echo "RESULT: PASS - the container design looks complete."
    exit 0
fi
echo "RESULT: INCOMPLETE - see the [FAIL] lines above."
exit 1
