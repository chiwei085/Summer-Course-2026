#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "lab_source"
WORKSPACE = ROOT / "workspace"
LAB = WORKSPACE / "git-merge-lab"

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


def write_controller(header: str, source: str, test: str) -> None:
    write_text(LAB / "include" / "velocity_controller.hpp", header)
    write_text(LAB / "src" / "velocity_controller.cpp", source)
    write_text(LAB / "tests" / "test_velocity_controller.cpp", test)


def commit(message: str, timestamp: str) -> None:
    run(["git", "add", "."])
    run(
        ["git", "commit", "-m", message],
        env={
            "GIT_AUTHOR_DATE": timestamp,
            "GIT_COMMITTER_DATE": timestamp,
        },
    )


def smoke_check() -> None:
    build_dir = LAB / ".verify_build" / "initial"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    run(["cmake", "-S", ".", "-B", str(build_dir)])
    run(["cmake", "--build", str(build_dir)])
    run(["ctest", "--test-dir", str(build_dir), "--output-on-failure"])
    status = run(["git", "status", "--short"]).stdout.strip()
    if status:
        raise RuntimeError(f"generated repository is not clean:\n{status}")


def main() -> None:
    if LAB.exists():
        shutil.rmtree(LAB)
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SOURCE, LAB)

    run(["git", "init", "-b", "main"])
    run(["git", "config", "user.name", AUTHOR_NAME])
    run(["git", "config", "user.email", AUTHOR_EMAIL])
    run(["git", "config", "core.autocrlf", "false"])
    run(["git", "config", "core.eol", "lf"])

    write_controller(HEADER_OLD, SRC_ANCESTOR, TEST_OLD)
    commit("initial velocity controller", "2026-01-01T09:00:00+00:00")

    run(["git", "switch", "-c", "feature/safety-limit"])
    write_controller(HEADER_OLD, SRC_FEATURE, TEST_OLD)
    commit("feat: clamp controller output for safety", "2026-01-01T09:10:00+00:00")

    run(["git", "switch", "main"])
    write_controller(HEADER_STRUCTURED, SRC_MAIN, TEST_STRUCTURED)
    commit("refactor: introduce structured velocity types", "2026-01-01T09:20:00+00:00")

    run(["git", "switch", "main"])
    smoke_check()

    print("Generated workspace/git-merge-lab")
    print()
    print("Next steps:")
    print("  cd workspace/git-merge-lab")
    print("  python3 tools/tutor.py")


if __name__ == "__main__":
    main()

