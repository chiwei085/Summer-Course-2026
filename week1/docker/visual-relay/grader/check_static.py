#!/usr/bin/env python3
"""Static design checks for the Visual Relay containerization assignment.

Every check is independent and always runs (a failure never skips the rest),
so a student gets one report that lists everything that is still wrong
instead of stopping at the first problem. `grade.sh` parses the machine
readable "STATIC_SCORE passed total" line printed at the end.
"""
from __future__ import annotations

import pathlib
import re
import sys
from typing import Callable

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def source_text() -> str:
    chunks = []
    for sub in ("include", "src"):
        for path in (ROOT / sub).rglob("*"):
            if path.is_file():
                chunks.append(path.read_text(encoding="utf-8"))
    return "\n".join(chunks)


def dockerfile_stages(dockerfile: str) -> dict[str, tuple[str, str]]:
    """Map stage name -> (base stage/image, block text) for every `FROM ... AS` line."""
    stages: dict[str, tuple[str, str]] = {}
    for match in re.finditer(
        r"FROM\s+(\S+)\s+AS\s+(\S+)(.*?)(?=\nFROM\s|\Z)", dockerfile, re.DOTALL
    ):
        base, name, block = match.groups()
        stages[name] = (base, block)
    return stages


def effective_runtime_user(stages: dict[str, tuple[str, str]], stage: str) -> str | None:
    """Last `USER` in effect for `stage`, resolved through inherited base stages."""
    seen: set[str] = set()
    while stage in stages and stage not in seen:
        seen.add(stage)
        base, block = stages[stage]
        users = re.findall(r"^USER\s+(\S+)", block, re.MULTILINE)
        if users:
            return users[-1]
        stage = base
    return None


Check = Callable[[], tuple[bool, str]]


def check_no_privileged_escapes() -> tuple[bool, str]:
    compose = read("compose.yaml")
    readme = read("README.md")
    forbidden = ["privileged: true", "network_mode: host", "xhost +"]
    hits = [t for t in forbidden if t in compose or t in readme]
    return (not hits, f"forbidden token(s) present: {hits}" if hits else "ok")


def check_no_boost() -> tuple[bool, str]:
    dockerfile = read("Dockerfile")
    cmake = read("CMakeLists.txt")
    src = source_text()
    forbidden = ["boost/asio", "Boost::", "libboost", "find_package(Boost"]
    hits = [t for t in forbidden if t in dockerfile or t in cmake or t in src]
    return (not hits, f"forbidden Boost dependency: {hits}" if hits else "ok")


def check_network_separation() -> tuple[bool, str]:
    compose = read("compose.yaml")
    nets = ["camera-net", "handoff-net", "control-net"]
    missing = [n for n in nets if n not in compose]
    return (not missing, f"missing networks: {missing}" if missing else "ok")


def check_read_only_rootfs() -> tuple[bool, str]:
    compose = read("compose.yaml")
    ok = "read_only: true" in compose
    return (ok, "ok" if ok else "runtime root filesystem is not read-only")


def check_tmpfs() -> tuple[bool, str]:
    compose = read("compose.yaml")
    ok = "tmpfs:" in compose
    return (ok, "ok" if ok else "runtime tmpfs mount is missing")


def check_no_new_privileges() -> tuple[bool, str]:
    compose = read("compose.yaml")
    ok = "no-new-privileges:true" in compose
    return (ok, "ok" if ok else "no-new-privileges:true is missing")


def check_runtime_targets() -> tuple[bool, str]:
    compose = read("compose.yaml")
    dockerfile = read("Dockerfile")
    missing = []
    for target in ("simulator-runtime", "scout-runtime", "catcher-runtime"):
        if f"target: {target}" not in compose:
            missing.append(f"compose target {target}")
        if not re.search(rf"FROM\s+\S+\s+AS\s+{target}\b", dockerfile):
            missing.append(f"Dockerfile stage {target}")
    return (not missing, f"missing: {missing}" if missing else "ok")


def check_dependencies_stage() -> tuple[bool, str]:
    dockerfile = read("Dockerfile")
    ok = "FROM base-build AS dependencies" in dockerfile
    return (ok, "ok" if ok else "multi-stage dependencies stage is missing")


def check_cache_mounts() -> tuple[bool, str]:
    dockerfile = read("Dockerfile")
    ok = "--mount=type=cache" in dockerfile
    return (ok, "ok" if ok else "BuildKit cache mounts are missing")


def check_ccache() -> tuple[bool, str]:
    dockerfile = read("Dockerfile")
    ok = "ccache" in dockerfile
    return (ok, "ok" if ok else "ccache is missing from the build stages")


def check_ninja_generator() -> tuple[bool, str]:
    dockerfile = read("Dockerfile")
    ok = " -G Ninja" in dockerfile
    return (ok, "ok" if ok else "Docker builds must use the Ninja CMake generator")


def check_dockerignore() -> tuple[bool, str]:
    dockerignore = read(".dockerignore")
    missing = [t for t in (".git", "build") if t not in dockerignore]
    return (not missing, f".dockerignore misses: {missing}" if missing else "ok")


def check_no_hardcoded_ips() -> tuple[bool, str]:
    compose = read("compose.yaml")
    ip_literals = re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", compose)
    bad = [ip for ip in ip_literals if ip != "127.0.0.1"]
    return (not bad, f"hard-coded service IPs found: {bad}" if bad else "ok")


def check_pinned_sdl3() -> tuple[bool, str]:
    dockerfile = read("Dockerfile")
    match = re.search(r"SDL3_TAG=(\S+)", dockerfile)
    if not match:
        return (False, "SDL3_TAG build arg is missing")
    tag = match.group(1)
    floating = {"main", "master", "latest", "HEAD"}
    ok = tag not in floating
    return (ok, "ok" if ok else f"SDL3_TAG must pin a release, not '{tag}'")


def check_pinned_base_image() -> tuple[bool, str]:
    dockerfile = read("Dockerfile")
    match = re.search(r"ARG UBUNTU_VERSION=(\S+)", dockerfile)
    if not match:
        return (False, "UBUNTU_VERSION build arg is missing")
    ok = match.group(1) != "latest" and "ubuntu:latest" not in dockerfile
    return (ok, "ok" if ok else "base image must pin a version, not 'latest'")


def check_non_root_runtime_users() -> tuple[bool, str]:
    dockerfile = read("Dockerfile")
    stages = dockerfile_stages(dockerfile)
    missing = []
    for stage in ("simulator-runtime", "scout-runtime", "catcher-runtime"):
        user = effective_runtime_user(stages, stage)
        if user is None or user.split(":")[0] == "root":
            missing.append(stage)
    return (not missing, f"runs as root in stage(s): {missing}" if missing else "ok")


def check_resource_limits() -> tuple[bool, str]:
    compose = read("compose.yaml")
    services = re.split(r"\n  (?=\S+:\n)", compose)
    missing = []
    for name in ("relay-simulator", "scout-station", "catcher-station"):
        block = next((s for s in services if s.startswith(name + ":")), "")
        if "cpus:" not in block or "memory:" not in block:
            missing.append(name)
    return (not missing, f"missing cpu/memory limits: {missing}" if missing else "ok")


def check_healthchecks() -> tuple[bool, str]:
    compose = read("compose.yaml")
    services = re.split(r"\n  (?=\S+:\n)", compose)
    missing = []
    for name in ("relay-simulator", "scout-station", "catcher-station"):
        block = next((s for s in services if s.startswith(name + ":")), "")
        if "healthcheck-service.sh" not in block:
            missing.append(name)
        if "sleep" in block.split("healthcheck:", 1)[-1].split("deploy:", 1)[0]:
            missing.append(f"{name} (uses a fixed sleep instead of a real probe)")
    return (not missing, f"healthcheck problem(s): {missing}" if missing else "ok")


CHECKS: list[tuple[str, Check]] = [
    ("no privileged/host-network/xhost escapes", check_no_privileged_escapes),
    ("no Boost dependency", check_no_boost),
    ("camera/handoff/control network separation", check_network_separation),
    ("read-only runtime root filesystem", check_read_only_rootfs),
    ("writable tmpfs for /tmp", check_tmpfs),
    ("no-new-privileges enabled", check_no_new_privileges),
    ("dedicated runtime stage per service", check_runtime_targets),
    ("multi-stage dependencies build", check_dependencies_stage),
    ("BuildKit cache mounts", check_cache_mounts),
    ("ccache wired into the build", check_ccache),
    ("Ninja CMake generator in Docker builds", check_ninja_generator),
    (".dockerignore excludes .git/build", check_dockerignore),
    ("service DNS instead of hard-coded IPs", check_no_hardcoded_ips),
    ("SDL3 dependency pinned to a release tag", check_pinned_sdl3),
    ("base image pinned to a fixed version", check_pinned_base_image),
    ("runtime containers run as non-root", check_non_root_runtime_users),
    ("per-service cpu/memory limits", check_resource_limits),
    ("readiness-mark based healthchecks", check_healthchecks),
]


def main() -> int:
    passed = 0
    for name, check in CHECKS:
        ok, detail = check()
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] static: {name} ({detail})")
        passed += int(ok)

    total = len(CHECKS)
    print(f"STATIC_SCORE {passed} {total}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
