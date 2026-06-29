#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "lab_source"
WORKSPACE = ROOT / "workspace"
LAB = WORKSPACE / "git-merge-lab"
TEMP_LAB = WORKSPACE / ".git-merge-lab.tmp"

AUTHOR_NAME = "Git Merge Tutor"
AUTHOR_EMAIL = "git-merge-tutor@example.invalid"


HEADER_OLD = """#pragma once

class VelocityController {
public:
    double compute_command(
        double current_velocity,
        double target_velocity) const;
};
"""


HEADER_STRUCTURED = """#pragma once

struct VelocityReading {
    double meters_per_second;
};

struct VelocityTarget {
    double desired_meters_per_second;
};

class VelocityController {
public:
    double compute_command(
        const VelocityReading& reading,
        const VelocityTarget& target) const;
};
"""


SRC_ANCESTOR = """#include "velocity_controller.hpp"

double VelocityController::compute_command(
    double current_velocity,
    double target_velocity) const
{
    return target_velocity - current_velocity;
}
"""


SRC_FEATURE = """#include "velocity_controller.hpp"

#include <algorithm>

double VelocityController::compute_command(
    double current_velocity,
    double target_velocity) const
{
    const double error =
        target_velocity - current_velocity;

    return std::clamp(error, -2.0, 2.0);
}
"""


SRC_MAIN = """#include "velocity_controller.hpp"

double VelocityController::compute_command(
    const VelocityReading& reading,
    const VelocityTarget& target) const
{
    return target.desired_meters_per_second
         - reading.meters_per_second;
}
"""


TEST_OLD = """#include "velocity_controller.hpp"

#include <cmath>
#include <iostream>

namespace {

bool close_to(double actual, double expected)
{
    return std::abs(actual - expected) < 1e-9;
}

}  // namespace

int main()
{
    const VelocityController controller;
    const double command = controller.compute_command(1.0, 1.5);

    if (!close_to(command, 0.5)) {
        std::cerr << "expected 0.5, got " << command << '\\n';
        return 1;
    }

    return 0;
}
"""


TEST_STRUCTURED = """#include "velocity_controller.hpp"

#include <cmath>
#include <iostream>

namespace {

bool close_to(double actual, double expected)
{
    return std::abs(actual - expected) < 1e-9;
}

}  // namespace

int main()
{
    const VelocityController controller;
    const VelocityReading reading{1.0};
    const VelocityTarget target{1.5};

    const double command = controller.compute_command(reading, target);
    if (!close_to(command, 0.5)) {
        std::cerr << "expected 0.5, got " << command << '\\n';
        return 1;
    }

    return 0;
}
"""


def run(args: list[str], cwd: Path = LAB, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    merged_env.update(
        {
            "LC_ALL": "C",
            "LANG": "C",
            "GIT_AUTHOR_NAME": AUTHOR_NAME,
            "GIT_AUTHOR_EMAIL": AUTHOR_EMAIL,
            "GIT_COMMITTER_NAME": AUTHOR_NAME,
            "GIT_COMMITTER_EMAIL": AUTHOR_EMAIL,
        }
    )
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=cwd,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_controller(repo: Path, header: str, source: str, test: str) -> None:
    write_text(repo / "include" / "velocity_controller.hpp", header)
    write_text(repo / "src" / "velocity_controller.cpp", source)
    write_text(repo / "tests" / "test_velocity_controller.cpp", test)


def commit(repo: Path, message: str, timestamp: str) -> None:
    run(["git", "add", "."], cwd=repo)
    run(
        ["git", "commit", "-m", message],
        cwd=repo,
        env={
            "GIT_AUTHOR_DATE": timestamp,
            "GIT_COMMITTER_DATE": timestamp,
        },
    )


def smoke_check(repo: Path) -> None:
    build_dir = repo / ".verify_build" / "initial"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    run(["cmake", "-S", ".", "-B", str(build_dir)], cwd=repo)
    run(["cmake", "--build", str(build_dir)], cwd=repo)
    run(["ctest", "--test-dir", str(build_dir), "--output-on-failure"], cwd=repo)
    run([sys.executable, "verify_lab.py"], cwd=repo)
    for name in [".verify_build", ".verify_checks"]:
        path = repo / name
        if path.exists():
            shutil.rmtree(path)
    status = run(["git", "status", "--short"], cwd=repo).stdout.strip()
    if status:
        raise RuntimeError(f"generated repository is not clean:\n{status}")


def remove_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def build_lab(repo: Path) -> None:
    shutil.copytree(SOURCE, repo)

    run(["git", "init"], cwd=repo)
    run(["git", "checkout", "-b", "main"], cwd=repo)
    run(["git", "config", "user.name", AUTHOR_NAME], cwd=repo)
    run(["git", "config", "user.email", AUTHOR_EMAIL], cwd=repo)
    run(["git", "config", "core.autocrlf", "false"], cwd=repo)
    run(["git", "config", "core.eol", "lf"], cwd=repo)

    write_controller(repo, HEADER_OLD, SRC_ANCESTOR, TEST_OLD)
    commit(repo, "initial velocity controller", "2026-01-01T09:00:00+00:00")

    run(["git", "checkout", "-b", "feature/safety-limit"], cwd=repo)
    write_controller(repo, HEADER_OLD, SRC_FEATURE, TEST_OLD)
    commit(repo, "feat: clamp controller output for safety", "2026-01-01T09:10:00+00:00")

    run(["git", "checkout", "main"], cwd=repo)
    write_controller(repo, HEADER_STRUCTURED, SRC_MAIN, TEST_STRUCTURED)
    commit(repo, "refactor: introduce structured velocity types", "2026-01-01T09:20:00+00:00")

    run(["git", "checkout", "main"], cwd=repo)
    smoke_check(repo)


def main() -> None:
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    remove_path(TEMP_LAB)

    try:
        build_lab(TEMP_LAB)
        remove_path(LAB)
        TEMP_LAB.rename(LAB)
    except Exception:
        remove_path(TEMP_LAB)
        raise

    print("Generated workspace/git-merge-lab")
    print()
    print("Next steps:")
    print("  cd workspace/git-merge-lab")
    print("  python3 tools/tutor.py")


if __name__ == "__main__":
    main()
