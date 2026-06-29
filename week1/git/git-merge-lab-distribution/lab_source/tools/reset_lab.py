#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
MAIN_COMMIT_MESSAGE = "refactor: introduce structured velocity types"


def run(args: list[str], check: bool = False) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        raise RuntimeError((result.stdout + result.stderr).strip())
    return result


def merge_in_progress() -> bool:
    return (REPO / ".git" / "MERGE_HEAD").exists()


def find_main_checkpoint() -> str:
    log = run(["git", "log", "--all", "--format=%H%x00%s"], check=True).stdout.splitlines()
    for line in log:
        commit_hash, _, subject = line.partition("\x00")
        if subject == MAIN_COMMIT_MESSAGE:
            return commit_hash
    raise RuntimeError(f"could not find checkpoint commit: {MAIN_COMMIT_MESSAGE}")


def remove_generated_dirs() -> None:
    for name in [".tutor_build", ".tutor_checks", ".verify_build", ".verify_checks", "build"]:
        path = REPO / name
        if path.exists():
            shutil.rmtree(path)


def main() -> None:
    if merge_in_progress():
        run(["git", "merge", "--abort"], check=True)

    checkpoint = find_main_checkpoint()
    run(["git", "switch", "main"], check=True)
    run(["git", "reset", "--hard", checkpoint], check=True)
    remove_generated_dirs()

    print("Lab reset complete.")
    print("  branch: main")
    print("  working tree: clean")


if __name__ == "__main__":
    main()

