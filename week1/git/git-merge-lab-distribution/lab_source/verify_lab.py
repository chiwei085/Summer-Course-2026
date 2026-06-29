#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO = Path(__file__).resolve().parent
INITIAL_MESSAGE = "initial velocity controller"
FEATURE_MESSAGE = "feat: clamp controller output for safety"
MAIN_MESSAGE = "refactor: introduce structured velocity types"
MERGE_MESSAGE = "merge: integrate safety limit with structured API"
REQUIRED_MESSAGES = {INITIAL_MESSAGE, FEATURE_MESSAGE, MAIN_MESSAGE}


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str = ""


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def require(args: list[str]) -> str:
    result = run(args)
    if result.returncode != 0:
        raise RuntimeError((result.stdout + result.stderr).strip())
    return result.stdout


def clean_check_dirs() -> None:
    for name in [".verify_build", ".verify_checks"]:
        path = REPO / name
        if path.exists():
            shutil.rmtree(path)
    (REPO / ".verify_checks").mkdir(parents=True, exist_ok=True)


def compile_program(source_name: str, source: str, output_name: str) -> subprocess.CompletedProcess[str]:
    check_dir = REPO / ".verify_checks"
    source_path = check_dir / source_name
    output_path = check_dir / output_name
    source_path.write_text(source, encoding="utf-8", newline="\n")
    return run(
        [
            "c++",
            "-std=c++17",
            "-Iinclude",
            "src/velocity_controller.cpp",
            str(source_path),
            "-o",
            str(output_path),
        ]
    )


def project_build_check() -> CheckResult:
    build_dir = REPO / ".verify_build" / "project"
    result = run(["cmake", "-S", ".", "-B", str(build_dir)])
    if result.returncode != 0:
        return CheckResult("Build", False, result.stderr.strip() or result.stdout.strip())
    result = run(["cmake", "--build", str(build_dir)])
    return CheckResult("Build", result.returncode == 0, result.stderr.strip() or result.stdout.strip())


def api_check() -> CheckResult:
    source = """#include "velocity_controller.hpp"

int main()
{
    const VelocityController controller;
    const VelocityReading reading{1.0};
    const VelocityTarget target{1.5};
    (void)controller.compute_command(reading, target);
    return 0;
}
"""
    result = compile_program("api_check.cpp", source, "api_check")
    return CheckResult("API compatibility", result.returncode == 0, result.stderr.strip() or result.stdout.strip())


def behavior_check() -> CheckResult:
    source = """#include "velocity_controller.hpp"

#include <cmath>
#include <iostream>

bool close_to(double actual, double expected)
{
    return std::abs(actual - expected) < 1e-9;
}

int main()
{
    const VelocityController controller;
    int failed = 0;

    auto check = [&](const char* name, double current, double target_value, double expected) {
        const VelocityReading reading{current};
        const VelocityTarget target{target_value};
        const double actual = controller.compute_command(reading, target);
        if (!close_to(actual, expected)) {
            std::cout << "FAIL: " << name << " expected " << expected << " got " << actual << "\\n";
            ++failed;
        }
    };

    check("base behavior", 1.0, 1.5, 0.5);
    check("positive safety limit", 0.0, 10.0, 2.0);
    check("negative safety limit", 10.0, 0.0, -2.0);
    check("semantic direction", 1.0, 1.25, 0.25);

    return failed == 0 ? 0 : 1;
}
"""
    compile_result = compile_program("behavior_check.cpp", source, "behavior_check")
    if compile_result.returncode != 0:
        return CheckResult("Strict behavior", False, compile_result.stderr.strip() or compile_result.stdout.strip())
    result = run([str(REPO / ".verify_checks" / "behavior_check")])
    return CheckResult("Strict behavior", result.returncode == 0, result.stdout.strip() or result.stderr.strip())


def strict_checks() -> list[CheckResult]:
    clean_check_dirs()
    results = [project_build_check(), api_check()]
    if results[-1].passed:
        results.append(behavior_check())
    else:
        results.append(CheckResult("Strict behavior", False, "API compatibility failed"))
    return results


def smoke_build() -> CheckResult:
    clean_check_dirs()
    return project_build_check()


def branch_exists(name: str) -> bool:
    return run(["git", "rev-parse", "--verify", name]).returncode == 0


def head_parent_count() -> int:
    line = require(["git", "rev-list", "--parents", "-n", "1", "HEAD"]).strip()
    return max(0, len(line.split()) - 1)


def commit_map() -> dict[str, str]:
    commits: dict[str, str] = {}
    for line in require(["git", "log", "--all", "--format=%H%x00%s"]).splitlines():
        commit_hash, _, subject = line.partition("\x00")
        commits.setdefault(subject, commit_hash)
    return commits


def parent_hashes(commit_hash: str) -> list[str]:
    line = require(["git", "rev-list", "--parents", "-n", "1", commit_hash]).strip()
    parts = line.split()
    return parts[1:]


def verify_graph() -> dict[str, str]:
    if not branch_exists("main"):
        raise RuntimeError("missing branch: main")
    if not branch_exists("feature/safety-limit"):
        raise RuntimeError("missing branch: feature/safety-limit")

    commits = commit_map()
    missing = REQUIRED_MESSAGES - set(commits)
    if missing:
        raise RuntimeError("missing expected commits: " + ", ".join(sorted(missing)))

    initial = commits[INITIAL_MESSAGE]
    main_refactor = commits[MAIN_MESSAGE]
    feature = commits[FEATURE_MESSAGE]

    if parent_hashes(main_refactor) != [initial]:
        raise RuntimeError("main refactor commit does not descend from the expected ancestor")
    if parent_hashes(feature) != [initial]:
        raise RuntimeError("feature commit does not descend from the expected ancestor")

    return commits


def print_result(result: CheckResult) -> None:
    print(f"{result.name}: {'PASS' if result.passed else 'FAIL'}")
    if result.detail and not result.passed:
        print(result.detail)


def main() -> int:
    try:
        commits = verify_graph()

        status = require(["git", "status", "--short"]).strip()
        parent_count = head_parent_count()

        if parent_count < 2:
            result = smoke_build()
            print_result(result)
            if not result.passed:
                return 1
            if status:
                print("Lab generated, but working tree is not clean.")
                print(status)
                return 1
            print("Lab generated and ready.")
            print("Final merge not completed yet.")
            return 0

        subject = require(["git", "show", "-s", "--format=%s", "HEAD"]).strip()
        if subject != MERGE_MESSAGE:
            raise RuntimeError(f"unexpected merge commit subject: {subject}")
        parents = set(parent_hashes("HEAD"))
        expected_parents = {commits[MAIN_MESSAGE], commits[FEATURE_MESSAGE]}
        if parents != expected_parents:
            raise RuntimeError("merge commit does not connect the expected main and feature commits")

        results = strict_checks()
        for result in results:
            print_result(result)
        if not all(result.passed for result in results):
            return 1
        if status:
            print("Strict checks passed, but working tree is not clean.")
            print(status)
            return 1

        print("Final merge commit present.")
        print("Strict tests passed.")
        return 0

    except Exception as error:
        print(f"verify_lab.py: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
