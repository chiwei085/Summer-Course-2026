# Visual Relay

Containerizing a distributed cross-camera robot vision system.

This assignment simulates a realistic container deployment: one simulator
shows the authoritative conveyor world and publishes camera data, two
workstation containers show their own first-person camera views, and the
services coordinate over separate Docker networks.

## Requirements

- Linux desktop
- Docker Engine
- Docker Compose v2
- Wayland or X11/XWayland
- x86-64

The runtime GUI containers require a real Linux display server. There is no
headless GUI fallback.

## What You Will Run

```text
relay-simulator  GUI conveyor world, camera datagrams, control lease
scout-station    GUI first-person camera receiver, UDP updates, TCP handoff sender
catcher-station  GUI first-person camera receiver, UDP stale checks, TCP handoff receiver
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

All three runtime services receive the host GUI resources needed by SDL3. The
simulator owns the conveyor display; `scout-station` and `catcher-station`
render only their respective camera streams and overlays.

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

The simulator produces deterministic raw RGB camera datagrams and renders the
full conveyor world through SDL3. The workstation windows display those
simulator-published first-person camera pixels, then add local overlays. The
station camera views are horizontally mirrored relative to the simulator world
overview and render the rear face of objects, matching the robot camera poses.
