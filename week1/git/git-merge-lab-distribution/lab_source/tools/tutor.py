#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
PATCH_DIR = REPO / "tools" / "patches"

AUTHOR_ENV = {
    "GIT_AUTHOR_NAME": "Git Merge Tutor",
    "GIT_AUTHOR_EMAIL": "git-merge-tutor@example.invalid",
    "GIT_COMMITTER_NAME": "Git Merge Tutor",
    "GIT_COMMITTER_EMAIL": "git-merge-tutor@example.invalid",
    "GIT_AUTHOR_DATE": "2026-01-01T09:30:00+00:00",
    "GIT_COMMITTER_DATE": "2026-01-01T09:30:00+00:00",
}


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str = ""


def run(args: list[str], check: bool = False, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    merged_env.update({"LC_ALL": "C", "LANG": "C"})
    if env:
        merged_env.update(env)
    result = subprocess.run(
        args,
        cwd=REPO,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        raise RuntimeError(command_output(args, result))
    return result


def command_output(args: list[str], result: subprocess.CompletedProcess[str]) -> str:
    output = []
    output.append(f"$ {' '.join(args)}")
    if result.stdout:
        output.append(result.stdout.rstrip())
    if result.stderr:
        output.append(result.stderr.rstrip())
    return "\n".join(output)


def section(title: str) -> None:
    print()
    print(title)
    print("─" * 40)


def current_branch() -> str:
    return run(["git", "branch", "--show-current"], check=True).stdout.strip()


def working_tree_clean() -> bool:
    return run(["git", "status", "--short"], check=True).stdout.strip() == ""


def merge_in_progress() -> bool:
    return (REPO / ".git" / "MERGE_HEAD").exists()


def ask_choice(question: str, options: list[str], correct: str | None = None) -> str:
    print()
    print(question)
    for index, option in enumerate(options, start=1):
        print(f"[{index}] {option}")

    valid = {str(i) for i in range(1, len(options) + 1)}
    while True:
        answer = input("> ").strip()
        if answer not in valid:
            print("請輸入選項編號。")
            continue
        if correct is not None and answer != correct:
            print("這個選項沒有保留圖中的關鍵資訊，請再判斷一次。")
            continue
        return answer


def ask_candidate() -> str:
    print()
    print("Candidate strategies:")
    print()
    print("A. Keep main")
    print("   Preserve VelocityReading / VelocityTarget, but do not clamp output.")
    print()
    print("B. Keep feature")
    print("   Preserve std::clamp, but return to the old double, double API.")
    print()
    print("C. Integrate both")
    print("   Preserve the structured API and clamp the computed error.")
    print()
    print("D. Surface integration, wrong behavior")
    print("   Use the structured API and clamp, but compute the error backwards.")

    valid = {"A", "B", "C", "D"}
    while True:
        answer = input("\nChoose A, B, C, or D: ").strip().upper()
        if answer in valid:
            return answer
        print("請輸入 A、B、C 或 D。")


def print_observation() -> None:
    section("Git Merge Lab")
    print()
    print("Current branch:")
    print(f"  {current_branch()}")
    print()
    print("Working tree:")
    print("  clean" if working_tree_clean() else "  not clean")
    print()
    print("Available branches:")
    branches = run(["git", "branch", "--format", "%(refname:short)"], check=True).stdout.splitlines()
    branches = sorted(branches, key=lambda name: (name != "main", name))
    for branch in branches:
        print(f"  {branch}")
    print()
    print("* B refactor: introduce structured velocity types")
    print("| * C feat: clamp controller output for safety")
    print("|/")
    print("* A initial velocity controller")


def ensure_start_state() -> None:
    if merge_in_progress():
        run(["git", "merge", "--abort"])
    run(["git", "switch", "main"], check=True)

    parents = run(["git", "rev-list", "--parents", "-n", "1", "HEAD"], check=True).stdout.strip().split()
    if len(parents) > 2:
        print("This lab already has a merge commit on main.")
        print("Run python3 tools/reset_lab.py if you want to start over.")
        sys.exit(0)

    if not working_tree_clean():
        raise RuntimeError("Working tree is not clean. Run python3 tools/reset_lab.py before starting.")


def execute_merge() -> None:
    print()
    print("Plan:")
    print("  git merge feature/safety-limit")
    ask_choice(
        "你預期會發生什麼？",
        [
            "fast-forward",
            "自動合併且沒有衝突",
            "Git 停止並要求人工解決衝突",
            "feature 直接覆蓋 main",
        ],
    )
    result = run(["git", "merge", "feature/safety-limit"])
    print()
    print("Git output:")
    output = (result.stdout + result.stderr).strip()
    print(textwrap.indent(output, "  ") if output else "  <no output>")
    if result.returncode == 0:
        raise RuntimeError("Expected a merge conflict, but merge completed.")


def show_conflict() -> None:
    source = (REPO / "src" / "velocity_controller.cpp").read_text(encoding="utf-8")
    lines = source.splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith("<<<<<<<"))
    end = next(i for i, line in enumerate(lines) if line.startswith(">>>>>>>"))

    print()
    print("Conflict marker:")
    print()
    print("<<<<<<< HEAD")
    print("main 分支目前內容")
    print("=======")
    print("incoming branch 內容")
    print(">>>>>>> feature/safety-limit")
    print()
    print("Actual conflicting text:")
    print()
    print(textwrap.indent("\n".join(lines[start : end + 1]), "  "))

    ask_choice(
        "Git 此時缺少的是什麼？",
        [
            "檔案讀取權限",
            "C++ 編譯器",
            "對兩邊程式意圖的理解",
            "GitHub 帳號",
        ],
        correct="3",
    )
    print()
    print("Git 知道兩邊文字不同，但不知道新 API 與安全限制是否應該同時保留。")


def explain_ours_theirs() -> None:
    print()
    print("OURS / HEAD:")
    print("  使用新的 VelocityReading / VelocityTarget API")
    print("  沒有安全限制")
    print()
    print("THEIRS:")
    print("  使用舊的 double API")
    print("  有安全限制")

    ask_choice(
        "直接選擇 ours 會失去什麼？",
        [
            "safety invariant",
            "main branch",
            "Git history",
            "CMake",
        ],
        correct="1",
    )
    ask_choice(
        "直接選擇 theirs 會失去什麼？",
        [
            "feature branch name",
            "新的 VelocityReading / VelocityTarget API",
            "std::clamp",
            "merge conflict marker",
        ],
        correct="2",
    )


def parse_patch_bundle(path: Path) -> list[tuple[Path, str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    files: list[tuple[Path, str]] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("*** Begin File: "):
            raise RuntimeError(f"invalid patch bundle line: {line}")
        relative = Path(line.removeprefix("*** Begin File: ").strip())
        index += 1
        body: list[str] = []
        while index < len(lines) and lines[index] != "*** End File":
            body.append(lines[index])
            index += 1
        if index >= len(lines):
            raise RuntimeError(f"missing end marker in {path}")
        files.append((relative, "\n".join(body) + "\n"))
        index += 1
    return files


def apply_candidate(choice: str) -> str:
    patch_names = {
        "A": "keep_main.patch",
        "B": "keep_feature.patch",
        "C": "integrated.patch",
        "D": "broken_adapter.patch",
    }
    patch_name = patch_names[choice]
    for relative, content in parse_patch_bundle(PATCH_DIR / patch_name):
        target = REPO / relative
        target.write_text(content, encoding="utf-8", newline="\n")
    return patch_name


def clean_check_dirs() -> None:
    for name in [".tutor_build", ".tutor_checks"]:
        path = REPO / name
        if path.exists():
            shutil.rmtree(path)
    (REPO / ".tutor_checks").mkdir(parents=True, exist_ok=True)


def compile_program(source_name: str, source: str, output_name: str) -> subprocess.CompletedProcess[str]:
    check_dir = REPO / ".tutor_checks"
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
    build_dir = REPO / ".tutor_build" / "project"
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
    int passed = 0;
    int failed = 0;

    auto check = [&](const char* name, double current, double target_value, double expected) {
        const VelocityReading reading{current};
        const VelocityTarget target{target_value};
        const double actual = controller.compute_command(reading, target);
        if (close_to(actual, expected)) {
            std::cout << "PASS: " << name << "\\n";
            ++passed;
            return;
        }
        std::cout << "FAIL: " << name << " expected " << expected << " got " << actual << "\\n";
        ++failed;
    };

    check("base behavior", 1.0, 1.5, 0.5);
    check("positive safety limit", 0.0, 10.0, 2.0);
    check("negative safety limit", 10.0, 0.0, -2.0);
    check("semantic direction", 1.0, 1.25, 0.25);

    std::cout << "SUMMARY: " << passed << " passed, " << failed << " failed\\n";
    return failed == 0 ? 0 : 1;
}
"""
    compile_result = compile_program("behavior_check.cpp", source, "behavior_check")
    if compile_result.returncode != 0:
        return CheckResult("Behavior tests", False, compile_result.stderr.strip() or compile_result.stdout.strip())

    result = run([str(REPO / ".tutor_checks" / "behavior_check")])
    return CheckResult("Behavior tests", result.returncode == 0, result.stdout.strip() or result.stderr.strip())


def verify_candidate() -> list[CheckResult]:
    clean_check_dirs()
    results = [project_build_check(), api_check()]
    if results[-1].passed:
        results.append(behavior_check())
    else:
        results.append(CheckResult("Behavior tests", False, "skipped because the structured API caller did not compile"))
    return results


def print_results(results: list[CheckResult]) -> None:
    print()
    for result in results:
        print(f"{result.name}:")
        print("  PASS" if result.passed else "  FAIL")
        if result.name == "Behavior tests" and result.detail:
            for line in result.detail.splitlines():
                print(f"  {line}")


def explain_failure(choice: str) -> None:
    print()
    print("Interpretation:")
    if choice == "A":
        print("  The main branch API was preserved, but the incoming safety behavior was discarded.")
        print("  Failed property: compute_command must remain within [-2.0, 2.0].")
    elif choice == "B":
        print("  The safety behavior exists, but callers using VelocityReading / VelocityTarget no longer compile.")
        print("  Failed property: the refactored API from main must be preserved.")
    elif choice == "D":
        print("  The code contains the new API and std::clamp, but the command direction is reversed.")
        print("  Failed property: target > current must produce a positive command.")


def rebuild_conflict_checkpoint() -> None:
    if merge_in_progress():
        run(["git", "merge", "--abort"], check=True)
    run(["git", "switch", "main"], check=True)
    run(["git", "merge", "feature/safety-limit"])
    if not merge_in_progress():
        raise RuntimeError("Could not rebuild the merge conflict checkpoint.")


def handle_wrong_choice(choice: str) -> None:
    explain_failure(choice)
    ask_choice(
        "下一步應該做什麼？",
        [
            "因為編譯成功，所以直接 commit",
            "刪除失敗測試",
            "回到 conflict checkpoint，重新選擇整合策略",
            "使用 git push --force",
        ],
        correct="3",
    )
    rebuild_conflict_checkpoint()


def commit_resolution() -> None:
    print()
    print("Plan:")
    print("  git add src/velocity_controller.cpp")
    print("  git commit")
    ask_choice(
        "git add 在這裡表示什麼？",
        [
            "將檔案上傳到 GitHub",
            "告訴 Git 這個衝突已經完成解決",
            "建立新的 branch",
            "刪除 feature branch",
        ],
        correct="2",
    )
    run(["git", "add", "src/velocity_controller.cpp"], check=True)
    result = run(
        ["git", "commit", "-m", "merge: integrate safety limit with structured API"],
        env=AUTHOR_ENV,
    )
    if result.returncode != 0:
        raise RuntimeError(command_output(["git", "commit"], result))


def print_final_review() -> None:
    print()
    print("*   M merge: integrate safety limit with structured API")
    print("|\\")
    print("| * C feat: clamp controller output for safety")
    print("* | B refactor: introduce structured velocity types")
    print("|/")
    print("* A initial velocity controller")

    section("Lab completed")
    print()
    print("You observed:")
    print()
    observations = [
        "main and feature represented parallel histories",
        "both branches contained valid changes",
        "Git detected a textual conflict",
        "Git could not infer the intended program behavior",
        "accepting only ours discarded the safety feature",
        "accepting only theirs discarded the new API",
        "compilation alone was insufficient",
        "tests verified the integrated behavior",
        "the merge commit connected both histories",
    ]
    for item in observations:
        print(f"✓ {item}")

    print()
    print("Final repository status:")
    print(f"  branch: {current_branch()}")
    print("  working tree: clean" if working_tree_clean() else "  working tree: not clean")
    print("  tests: passed")
    print("  merge commit: present")


def main() -> None:
    try:
        ensure_start_state()
        print_observation()
        ask_choice(
            "這張圖表示什麼？",
            [
                "feature/safety-limit 是 main 的備份",
                "兩個分支從共同版本開始，各自產生不同修改",
                "feature/safety-limit 已經包含在 main",
                "main 一定比 feature/safety-limit 正確",
            ],
            correct="2",
        )

        print()
        print("main:")
        print("  - introduces VelocityReading")
        print("  - introduces VelocityTarget")
        print("  - changes the method interface")
        print()
        print("feature/safety-limit:")
        print("  - keeps the old interface")
        print("  - limits output to [-2.0, 2.0]")

        ask_choice(
            "這兩個分支是否可能同時具有價值？",
            [
                "不可能，只能保留一邊",
                "可以，一邊改善介面，一邊增加安全行為",
                "只有較新的 commit 有價值",
                "branch 名稱較長的比較重要",
            ],
            correct="2",
        )

        execute_merge()
        show_conflict()
        explain_ours_theirs()

        while True:
            choice = ask_candidate()
            patch_name = apply_candidate(choice)
            print()
            print(f"Applied: tools/patches/{patch_name}")
            results = verify_candidate()
            print_results(results)

            if all(result.passed for result in results) and choice == "C":
                commit_resolution()
                print_final_review()
                return

            handle_wrong_choice(choice)

    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(130)
    except Exception as error:
        print(f"\nTutor error: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
