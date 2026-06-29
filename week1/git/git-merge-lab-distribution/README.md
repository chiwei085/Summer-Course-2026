# Git Merge Lab

This distribution generates a small Git repository for practicing merge decisions.

The lab is for students who are new to Git or only know `clone`, `add`, and `commit`.
Most Git commands are executed by scripts. Students mainly observe, predict, decide,
and interpret the result.

## Start

```bash
python3 generate_lab.py
cd workspace/git-merge-lab
python3 tools/tutor.py
```

The generated repository contains a tiny C++ velocity controller. Two branches start
from the same ancestor:

- `main` refactors the API to named velocity types.
- `feature/safety-limit` keeps the old API but clamps output to `[-2.0, 2.0]`.

The goal is to merge both intentions: keep the new API and keep the safety limit.

## Requirements

- Python 3
- Git
- CMake
- A C++17 compiler

## Reset

From the generated repository:

```bash
python3 tools/reset_lab.py
```

This returns the lab to the clean pre-merge `main` state.

