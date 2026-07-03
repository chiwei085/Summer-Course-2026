"""Root dispatcher for every week2 lab.

Each lab folder (`basic_*/`) is a self-contained project with its own
`src/train.py` (and, once a lab reaches that stage, `src/explore.py`)
Typer app. Every one of those packages is importlib-named `src`, so they
can't be imported into this same process without clobbering each other in
`sys.modules` -- this dispatcher shells out to `uv run` with the lab folder
as the working directory instead, which is exactly the manual
`cd <lab>/ && uv run --project .. python -m src.train ...` invocation each
LESSON.md documents. New labs need no registration here: dropping a
`src/train.py` into a new `basic_*/` folder is enough for it to show up.

Usage (from `week2/`):
    uv run python cli.py                                   # interactive picker
    uv run python cli.py list
    uv run python cli.py train basic_regression_classification --task classify --model linear
    uv run python cli.py explore basic_regression_classification metrics --run <run_id>
"""

import shlex
import subprocess
from pathlib import Path

import questionary
import typer

ROOT = Path(__file__).resolve().parent

app = typer.Typer(add_completion=False, no_args_is_help=False)

PASSTHROUGH = {"allow_extra_args": True, "ignore_unknown_options": True}


def discover_labs() -> dict[str, Path]:
    return {
        d.name: d
        for d in sorted(ROOT.iterdir())
        if d.is_dir() and (d / "src" / "train.py").exists()
    }


def _lesson_summary(lab_dir: Path) -> str:
    lesson = lab_dir / "LESSON.md"
    if not lesson.exists():
        return lab_dir.name
    for line in lesson.read_text(encoding="utf-8").splitlines():
        if line.startswith("**對應主線**"):
            return line.removeprefix("**對應主線**：").strip()
    return lesson.read_text(encoding="utf-8").splitlines()[0].lstrip("#").strip()


def _resolve_lab(labs: dict[str, Path], lab: str | None) -> str:
    if lab is None:
        choice = questionary.select(
            "要跑哪一個 lab？",
            choices=[
                questionary.Choice(title=f"{name}  —  {_lesson_summary(d)}", value=name)
                for name, d in labs.items()
            ],
        ).ask()
        if choice is None:
            raise typer.Exit(1)
        return choice
    if lab not in labs:
        raise typer.BadParameter(f"unknown lab {lab!r}; available: {', '.join(labs)}")
    return lab


def _extra_args(ctx: typer.Context) -> list[str]:
    if ctx.args:
        return ctx.args
    text = questionary.text(
        "額外參數？（例如 --task classify --model mlp，留空使用該 lab 的預設值）",
        default="",
    ).ask()
    return shlex.split(text) if text else []


def _dispatch(lab_dir: Path, module: str, extra_args: list[str]) -> None:
    cmd = ["uv", "run", "--project", "..", "python", "-m", module, *extra_args]
    typer.echo(f"$ (cd {lab_dir.relative_to(ROOT)} && {shlex.join(cmd)})")
    result = subprocess.run(cmd, cwd=lab_dir)
    raise typer.Exit(result.returncode)


@app.command("list")
def list_labs() -> None:
    """列出目前有 train.py 的 lab。"""
    labs = discover_labs()
    if not labs:
        typer.echo("找不到任何 lab（沒有 basic_*/src/train.py）")
        raise typer.Exit(1)
    for name, d in labs.items():
        has_explore = "explore" if (d / "src" / "explore.py").exists() else "-"
        typer.echo(f"{name:32s} [{has_explore:7s}]  {_lesson_summary(d)}")


@app.command(context_settings=PASSTHROUGH)
def train(
    ctx: typer.Context,
    lab: str = typer.Argument(None, help="lab 資料夾名稱；不填則進入互動選單"),
) -> None:
    """執行某個 lab 的 `src.train`；其餘參數原樣轉給它。"""
    labs = discover_labs()
    lab_name = _resolve_lab(labs, lab)
    extra = ctx.args if (ctx.args or lab is not None) else _extra_args(ctx)
    _dispatch(labs[lab_name], "src.train", extra)


@app.command(context_settings=PASSTHROUGH)
def explore(
    ctx: typer.Context,
    lab: str = typer.Argument(None, help="lab 資料夾名稱；不填則進入互動選單"),
) -> None:
    """執行某個 lab 的 `src.explore`；其餘參數原樣轉給它。"""
    labs = discover_labs()
    lab_name = _resolve_lab(labs, lab)
    lab_dir = labs[lab_name]
    if not (lab_dir / "src" / "explore.py").exists():
        raise typer.BadParameter(f"{lab_name} 還沒有 src/explore.py 可以查詢")
    extra = ctx.args if (ctx.args or lab is not None) else _extra_args(ctx)
    _dispatch(lab_dir, "src.explore", extra)


@app.callback(invoke_without_command=True)
def main(ctx: typer.Context) -> None:
    """不帶任何 subcommand 時，進入完整的互動選單（選 lab → 選動作）。"""
    if ctx.invoked_subcommand is not None:
        return
    labs = discover_labs()
    if not labs:
        typer.echo("找不到任何 lab（沒有 basic_*/src/train.py）")
        raise typer.Exit(1)
    lab_name = _resolve_lab(labs, None)
    lab_dir = labs[lab_name]

    actions = ["train"]
    if (lab_dir / "src" / "explore.py").exists():
        actions.append("explore")
    action = actions[0] if len(actions) == 1 else questionary.select("要做什麼？", choices=actions).ask()
    if action is None:
        raise typer.Exit(1)

    module = "src.train" if action == "train" else "src.explore"
    text = questionary.text(
        "額外參數？（例如 --task classify --model mlp，留空使用預設值）",
        default="",
    ).ask()
    _dispatch(lab_dir, module, shlex.split(text) if text else [])


if __name__ == "__main__":
    app()
