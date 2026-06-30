#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose config >/tmp/visual-relay-compose-config.yaml
python3 grader/check_static.py
docker build --target test -t visual-relay/test:reference .
docker build --target simulator-runtime -t visual-relay/simulator:reference .
docker build --target scout-runtime -t visual-relay/scout:reference .
docker build --target catcher-runtime -t visual-relay/catcher:reference .

check_runtime_image() {
    local image="$1"
    docker run --rm --entrypoint sh "$image" -c '
        for tool in g++ cmake ninja git make python3; do
            if command -v "$tool" >/dev/null 2>&1; then
                echo "unexpected runtime tool: $tool"
                exit 1
            fi
        done
        test -z "$(find /opt/visual-relay -name "*.cpp" -o -name CMakeCache.txt | head -n 1)"
    '
}

check_runtime_image visual-relay/simulator:reference
check_runtime_image visual-relay/scout:reference
check_runtime_image visual-relay/catcher:reference
