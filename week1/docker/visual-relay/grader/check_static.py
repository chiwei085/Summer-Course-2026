#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def main() -> int:
    compose = read("compose.yaml")
    dockerfile = read("Dockerfile")
    dockerignore = read(".dockerignore")
    cmake = read("CMakeLists.txt")
    source_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (ROOT / "include").rglob("*")
        if path.is_file()
    )
    source_text += "\n" + "\n".join(
        path.read_text(encoding="utf-8")
        for path in (ROOT / "src").rglob("*")
        if path.is_file()
    )

    forbidden = ["privileged: true", "network_mode: host", "xhost +"]
    for token in forbidden:
        require(token not in compose and token not in read("README.md"), f"forbidden token present: {token}")
    for token in ["boost/asio", "Boost::", "libboost", "find_package(Boost"]:
        require(token not in dockerfile and token not in cmake and token not in source_text, f"forbidden Boost dependency present: {token}")

    require("camera-net" in compose and "handoff-net" in compose and "control-net" in compose, "missing separated networks")
    require("read_only: true" in compose, "runtime root filesystem is not read-only")
    require("tmpfs:" in compose, "runtime tmpfs is missing")
    require("no-new-privileges:true" in compose, "no-new-privileges is missing")
    require("target: simulator-runtime" in compose, "simulator runtime target missing")
    require("target: scout-runtime" in compose, "scout runtime target missing")
    require("target: catcher-runtime" in compose, "catcher runtime target missing")
    require("FROM base-build AS dependencies" in dockerfile, "dependencies stage missing")
    require("FROM runtime-base AS simulator-runtime" in dockerfile, "simulator runtime stage missing")
    require(re.search(r"FROM\s+\S+\s+AS\s+scout-runtime", dockerfile), "scout runtime stage missing")
    require(re.search(r"FROM\s+\S+\s+AS\s+catcher-runtime", dockerfile), "catcher runtime stage missing")
    require("--mount=type=cache" in dockerfile, "BuildKit cache mounts missing")
    require("ccache" in dockerfile, "ccache missing")
    require(" -G Ninja" in dockerfile, "Docker builds must use the Ninja CMake generator")
    require(".git" in dockerignore and "build" in dockerignore, ".dockerignore misses basic exclusions")

    ip_literals = re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", compose)
    require(not [ip for ip in ip_literals if ip != "127.0.0.1"], f"hard-coded service IPs found: {ip_literals}")

    print("PASS: static checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
