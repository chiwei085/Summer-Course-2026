# Week 2

## Quick Start

From this directory (`week2/`):

```bash
uv sync

# Interactive menu: select a lab, then choose train or explore
uv run python cli.py

# Or specify the command directly
uv run python cli.py list
uv run python cli.py train basic_regression_classification --task classify --model linear
uv run python cli.py explore basic_regression_classification metrics --run <run_id>
```

Each `basic_*/` directory is a standalone lab. The `LESSON.md` file inside contains the lab’s step-by-step lesson material.

`cli.py` simply saves you from having to run `cd` manually. The underlying commands are exactly the same as those taught in each lab’s `LESSON.md`.
