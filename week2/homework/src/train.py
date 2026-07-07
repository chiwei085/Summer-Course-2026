"""CLI entry point: hand-rolled training loop for the fused VLA policy.

Same `--config` <- `configs/default.yaml` precedence, and the same
"epoch = steps_per_epoch random-window gradient steps" convention as
`basic_sequence_bc` and `basic_vision_representation` -- 50 episodes is
too small and too uneven in length for a fixed "one pass over the data"
definition to mean much.

Usage (from this directory):
    uv run --project .. python -m src.train
    uv run --project .. python -m src.train --epochs 20 --block-size 12
"""

import base64
import io
import json
from datetime import datetime
from pathlib import Path

import torch
import typer
import yaml
from PIL import Image

from src import config as config_mod
from src import data as data_mod
from src import report as report_mod
from src.models import build_model

app = typer.Typer(add_completion=False)

ARTIFACTS_ROOT = Path(__file__).resolve().parent.parent / "artifacts"

HPARAM_FIELDS = [
    "camera",
    "image_size",
    "patch_size",
    "max_instruction_len",
    "bins_per_dim",
    "block_size",
    "n_embd",
    "n_head",
    "n_vision_layer",
    "n_lang_layer",
    "n_action_layer",
    "dropout",
    "epochs",
    "steps_per_epoch",
    "lr",
    "batch_size",
    "seed",
    "val_episode",
    "prompt_len",
    "gen_length",
    "temperature",
    "n_samples",
    "run_id",
    "device",
]


def _grad_norm(parameters) -> float:
    sq_sums = [p.grad.detach().pow(2).sum() for p in parameters if p.grad is not None]
    return torch.stack(sq_sums).sum().sqrt().item() if sq_sums else 0.0


def _image_to_data_uri(image_uint8: torch.Tensor) -> str:
    arr = image_uint8.permute(1, 2, 0).numpy()
    buf = io.BytesIO()
    Image.fromarray(arr).save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


@app.command()
def main(
    config_path: str = typer.Option(
        None, "--config", "-c", help="yaml file overriding configs/default.yaml"
    ),
    camera: str = typer.Option(None, help="image | image2"),
    image_size: int = typer.Option(None, help="frames are resized to this before patchifying"),
    patch_size: int = typer.Option(None, help="vision patch size in pixels"),
    max_instruction_len: int = typer.Option(None, help="instruction padding/truncation length"),
    bins_per_dim: int = typer.Option(None, help="action tokenizer bins per axis"),
    block_size: int = typer.Option(None, help="action-chunk length in steps"),
    n_embd: int = typer.Option(None, help="shared embedding dim"),
    n_head: int = typer.Option(None, help="attention heads"),
    n_vision_layer: int = typer.Option(None, help="self-attention blocks in the vision trunk"),
    n_lang_layer: int = typer.Option(None, help="self-attention blocks in the language trunk"),
    n_action_layer: int = typer.Option(None, help="fusion blocks in the action decoder"),
    dropout: float = typer.Option(None),
    epochs: int = typer.Option(None, help="number of epochs"),
    steps_per_epoch: int = typer.Option(None, help="gradient steps per epoch"),
    lr: float = typer.Option(None, help="AdamW learning rate"),
    batch_size: int = typer.Option(None, help="windows per gradient step"),
    seed: int = typer.Option(None, help="random seed for split + init + sampling"),
    val_episode: int = typer.Option(
        None, help="held-out episode index for the per-epoch rollout sample"
    ),
    prompt_len: int = typer.Option(
        None, help="real action steps fed as context before rolling out"
    ),
    gen_length: int = typer.Option(None, help="action steps to roll out for the sample"),
    temperature: float = typer.Option(None, help="sampling temperature for the rollout"),
    n_samples: int = typer.Option(
        None, help="held-out windows shown in the per-epoch qualitative panel"
    ),
    run_id: str = typer.Option(None, help="artifact run id; auto-generated if omitted"),
    device: str = typer.Option(None, help="cuda | cpu; auto-detected if omitted"),
) -> None:
    cli_args = locals()
    cfg = config_mod.load_config(
        {field: cli_args[field] for field in HPARAM_FIELDS},
        config_path=config_path,
    )

    block_size = cfg["block_size"]
    epochs, steps_per_epoch = cfg["epochs"], cfg["steps_per_epoch"]
    lr, batch_size, seed = cfg["lr"], cfg["batch_size"], cfg["seed"]
    run_id, device = cfg["run_id"], cfg["device"]

    torch.manual_seed(seed)
    dev = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))
    gen = torch.Generator().manual_seed(seed)

    typer.echo(f"loading HuggingFaceVLA/smol-libero (camera={cfg['camera']}) ...")
    split = data_mod.make_split(cfg["bins_per_dim"], cfg["image_size"], camera=cfg["camera"])
    net = build_model(cfg, split.vocab_size).to(dev)

    optimizer = torch.optim.AdamW(net.parameters(), lr=lr)

    resolved_run_id = run_id or f"vla_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    run_dir = ARTIFACTS_ROOT / resolved_run_id
    for sub in ("checkpoints", "samples", "logs"):
        (run_dir / sub).mkdir(parents=True, exist_ok=True)

    config = {
        "model": "vla",
        "vocab_size": split.vocab_size,
        **{field: cfg[field] for field in HPARAM_FIELDS},
        "run_id": resolved_run_id,
        "device": str(dev),
    }
    (run_dir / "config.yaml").write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")

    metrics_path = run_dir / "metrics.jsonl"
    log_path = run_dir / "logs" / "train.log"
    step = 0
    with (
        metrics_path.open("w", encoding="utf-8") as metrics_f,
        log_path.open("w", encoding="utf-8") as log_f,
    ):
        log_f.write(f"run {resolved_run_id} start device={dev}\n")
        for epoch in range(1, epochs + 1):
            net.train()
            for _ in range(steps_per_epoch):
                images, instr, hist, targets = data_mod.get_batch(
                    split,
                    split.train_episodes,
                    block_size,
                    batch_size,
                    cfg["max_instruction_len"],
                    gen,
                )
                images = split.normalize_image(images).to(dev)
                instr, hist, targets = instr.to(dev), hist.to(dev), targets.to(dev)

                optimizer.zero_grad()
                logits = net(images, instr, hist)  # (B, T, ACTION_DIM, bins)
                loss = torch.nn.functional.cross_entropy(
                    logits.reshape(-1, split.bins_per_dim), targets.reshape(-1)
                )
                loss.backward()
                gnorm = _grad_norm(net.parameters())

                if not torch.isfinite(loss):
                    log_f.write(f"epoch {epoch} step {step}: non-finite loss, stopping\n")
                    raise RuntimeError("training diverged: non-finite loss")

                optimizer.step()
                step += 1

                action_l2 = split.action_l2_error(
                    logits.detach().argmax(dim=-1).cpu(), targets.cpu()
                )
                metrics_f.write(
                    json.dumps(
                        {
                            "step": step,
                            "epoch": epoch,
                            "loss": loss.item(),
                            "action_l2_error": action_l2,
                            "lr": lr,
                            "grad_norm": gnorm,
                        }
                    )
                    + "\n"
                )
            metrics_f.flush()

            val_loss, val_l2 = _eval_val(net, split, cfg, batch_size, dev, gen)
            torch.save(net.state_dict(), run_dir / "checkpoints" / f"epoch_{epoch}.pt")
            _write_epoch_sample(net, split, cfg, run_dir, epoch, dev, val_loss, val_l2)
            log_f.write(
                f"epoch {epoch} done loss={loss.item():.4f} val_loss={val_loss:.4f} val_l2={val_l2:.4f}\n"
            )
            log_f.flush()
            typer.echo(
                f"epoch {epoch}/{epochs} loss={loss.item():.4f} val_loss={val_loss:.4f} val_l2={val_l2:.4f}"
            )

    _write_fusion_snapshot(net, split, cfg, run_dir, dev)
    report_mod.write_report(run_dir, config)
    typer.echo(f"done: artifacts written to {run_dir}")


@torch.no_grad()
def _eval_val(net, split, cfg, batch_size, dev, gen) -> tuple[float, float]:
    net.eval()
    images, instr, hist, targets = data_mod.get_batch(
        split, split.val_episodes, cfg["block_size"], batch_size, cfg["max_instruction_len"], gen
    )
    images_n = split.normalize_image(images).to(dev)
    instr, hist_d, targets_d = instr.to(dev), hist.to(dev), targets.to(dev)
    logits = net(images_n, instr, hist_d)
    val_loss = torch.nn.functional.cross_entropy(
        logits.reshape(-1, split.bins_per_dim), targets_d.reshape(-1)
    ).item()
    val_l2 = split.action_l2_error(logits.argmax(dim=-1).cpu(), targets)
    return val_loss, val_l2


def _val_episode(split, cfg) -> int:
    return split.val_episodes[cfg["val_episode"] % len(split.val_episodes)]


@torch.no_grad()
def _write_epoch_sample(net, split, cfg, run_dir, epoch, dev, val_loss, val_l2) -> None:
    """A fixed panel of held-out windows: the frame the policy conditioned
    on, the instruction it was given, and the predicted vs. actual next
    action (decoded to raw units) -- the multimodal-input analog of
    `basic_vision_representation`'s dot-on-image panel. A real action isn't
    a point on the image plane here (it's a 7-DoF joint command), so the
    comparison is a numeric table instead of an overlay.
    """
    net.eval()
    ep = _val_episode(split, cfg)
    start, end = split.episode_bounds[ep]
    block_size = cfg["block_size"]
    n = cfg["n_samples"]
    max_offset = max(1, end - start - block_size - 1)
    offsets = [(i * max_offset) // n for i in range(n)]

    samples = []
    for offset in offsets:
        t0 = start + offset
        window_ids = split.encode_actions(split.actions[t0 : t0 + block_size + 1])
        image = split.images[t0]
        instruction = split.instructions[t0]

        images_b = split.normalize_image(image.unsqueeze(0)).to(dev)
        instr_b = (
            split.encode_instruction(instruction, cfg["max_instruction_len"]).unsqueeze(0).to(dev)
        )
        hist_b = window_ids[:-1].unsqueeze(0).to(dev)

        logits = net(images_b, instr_b, hist_b)  # (1, block_size, ACTION_DIM, bins)
        predicted_ids = logits[0, -1].argmax(dim=-1).cpu()  # last step, fullest context
        actual_ids = window_ids[-1]

        samples.append(
            {
                "image": _image_to_data_uri(image),
                "instruction": instruction,
                "predicted": split.decode_actions(predicted_ids).tolist(),
                "actual": split.decode_actions(actual_ids).tolist(),
            }
        )

    payload = {"epoch": epoch, "val_loss": val_loss, "val_action_l2": val_l2, "samples": samples}
    (run_dir / "samples" / f"epoch_{epoch}.json").write_text(json.dumps(payload), encoding="utf-8")


@torch.no_grad()
def _write_fusion_snapshot(net, split, cfg, run_dir, dev) -> None:
    """Cross-attention from the action decoder into the fused
    [vision tokens; language tokens] context, for one fixed held-out
    window -- direct evidence of the "VLM 式融合" mechanism: how much of
    the policy's attention lands on the image vs. on the instruction, and
    which patches / words it is.
    """
    net.eval()
    ep = _val_episode(split, cfg)
    start, end = split.episode_bounds[ep]
    block_size = cfg["block_size"]
    t0 = start + min(cfg["prompt_len"], end - start - block_size - 1)

    image = split.images[t0]
    instruction = split.instructions[t0]
    window_ids = split.encode_actions(split.actions[t0 : t0 + block_size + 1])

    images_b = split.normalize_image(image.unsqueeze(0)).to(dev)
    instr_ids = split.encode_instruction(instruction, cfg["max_instruction_len"])
    instr_b = instr_ids.unsqueeze(0).to(dev)
    hist_b = window_ids[:-1].unsqueeze(0).to(dev)

    _, attn = net(images_b, instr_b, hist_b, return_attn=True)  # (1, n_head, T, n_patches + L)
    avg_attn = attn[0].mean(dim=0).cpu()  # (T, n_patches + L), averaged over heads and query steps
    step_avg = avg_attn.mean(dim=0)  # (n_patches + L,)

    n_patches = (cfg["image_size"] // cfg["patch_size"]) ** 2
    patches_per_side = cfg["image_size"] // cfg["patch_size"]
    vision_attn = step_avg[:n_patches].view(patches_per_side, patches_per_side)
    lang_attn = step_avg[n_patches:]
    words = [w for w in data_mod.tokenize(instruction)][: cfg["max_instruction_len"]]

    payload = {
        "image": _image_to_data_uri(image),
        "instruction": instruction,
        "vision_grid": vision_attn.tolist(),
        "words": words,
        "word_attn": lang_attn[: len(words)].tolist(),
        "vision_attn_total": vision_attn.sum().item(),
        "language_attn_total": lang_attn.sum().item(),
    }
    (run_dir / "samples" / "fusion_snapshot.json").write_text(json.dumps(payload), encoding="utf-8")


if __name__ == "__main__":
    app()
