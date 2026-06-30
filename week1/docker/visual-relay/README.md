# Visual Relay

Containerizing a distributed cross-camera robot vision system.

This assignment simulates a realistic container deployment: one simulator
publishes camera data, two workstation containers show GUI views, and the
services coordinate over separate Docker networks.

## Requirements

- Linux desktop
- Docker Engine
- Docker Compose v2
- Wayland or X11/XWayland
- x86-64

The workstation containers require a real Linux display server. There is no
headless GUI fallback.

## What You Will Run

```text
relay-simulator  authoritative world, camera datagrams, control lease
scout-station    GUI, camera receiver, UDP track updates, TCP handoff sender
catcher-station  GUI, camera receiver, UDP stale checks, TCP handoff receiver
```

Networks are split by data plane:

```text
camera-net   simulator -> scout/catcher camera stream
handoff-net  scout <-> catcher UDP updates and TCP identity handoff
control-net  scout/catcher -> simulator control lease
```

## Start The System

From this directory:

```bash
./scripts/run-gui.sh
```

The script chooses Wayland when a Wayland socket is available, otherwise it uses
X11/XWayland. It builds the images and starts all three runtime services.

Explicit Wayland:

```bash
docker compose --profile runtime -f compose.yaml -f compose.gui-wayland.yaml up --build
```

Explicit X11:

```bash
docker compose --profile runtime -f compose.yaml -f compose.gui-x11.yaml up --build
```

The simulator never receives display sockets. Only `scout-station` and
`catcher-station` are granted the host GUI resources needed by SDL3.

## Stop And Clean Up

```bash
docker compose --profile runtime down --remove-orphans
```

## Run The Checks

Static and protocol checks:

```bash
python3 grader/check_static.py
cmake -S . -B build/protocol -G Ninja -DVISUAL_RELAY_BUILD_APPS=OFF
cmake --build build/protocol
ctest --test-dir build/protocol --output-on-failure
```

Container test target:

```bash
docker compose --profile grader up --build --abort-on-container-exit
```

Runtime and fault checks:

```bash
./scripts/inject-network-fault.sh udp-loss 2
./scripts/inject-network-fault.sh tcp-handoff-cut
./scripts/inject-network-fault.sh scout-restart
./scripts/inject-network-fault.sh catcher-restart
./scripts/inject-network-fault.sh simulator-restart
```

## What To Notice

- Multi-stage Docker builds with separate runtime targets.
- Docker BuildKit cache mounts and ccache.
- A pinned source build for SDL3 in the dependencies stage.
- Non-root runtime users, read-only root filesystems, tmpfs `/tmp`, resource limits.
- Service DNS instead of hard-coded container IPs.
- Separate UDP and TCP planes for realtime estimates and reliable handoff.
- Healthchecks based on readiness marks, not fixed sleep delays.
- A small project-owned C++20 socket wrapper, `rik_asio`.
- GUI display integration for Wayland and X11 without privileged containers.

The simulator produces deterministic camera datagrams and the workstation
windows render the live system state through SDL3.
