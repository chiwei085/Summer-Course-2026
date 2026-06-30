from __future__ import annotations

import hashlib
import json
import stat
import time
from pathlib import Path


CONFIG = Path("/etc/robot/navigation.yaml")
STATE_DIR = Path("/opt/field-lab/state")
AUDIT_LOG = STATE_DIR / "audit.log"
STATE_FILE = STATE_DIR / "navigation_state.json"
VALIDATED_FILE = STATE_DIR / "validated.sha256"
NAV_LOG = Path("/var/log/robot/navigation.log")
REPORT = Path("/var/log/robot/mission-report.txt")


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S %z")


def audit(message: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with AUDIT_LOG.open("a", encoding="utf-8") as handle:
        handle.write(f"{now()} {message}\n")


def nav_log(message: str) -> None:
    NAV_LOG.parent.mkdir(parents=True, exist_ok=True)
    with NAV_LOG.open("a", encoding="utf-8") as handle:
        handle.write(f"{now()} navigation.service: {message}\n")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_max_speed(path: Path) -> float:
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("max_speed:"):
            return float(stripped.split(":", 1)[1].strip())
    raise ValueError("max_speed is missing")


def config_error(path: Path) -> str:
    try:
        speed = read_max_speed(path)
    except Exception as error:
        return f"config error: {error}"
    if speed <= 0.0 or speed > 2.0:
        return f"config error: max_speed must be within (0.0, 2.0]; found: {speed:g}"
    return ""


def ownership_error(path: Path) -> str:
    info = path.stat()
    mode = stat.S_IMODE(info.st_mode)
    if info.st_uid != 0:
        return "config owner must be root"
    if group_name(info.st_gid) != "robot":
        return "config group must be robot"
    if mode != 0o640:
        return f"config mode must be 0640; found: {mode:04o}"
    return ""


def group_name(gid: int) -> str:
    for line in Path("/etc/group").read_text(encoding="utf-8").splitlines():
        name, _, raw_gid, _ = line.split(":", 3)
        if int(raw_gid) == gid:
            return name
    return str(gid)


def write_state(state: str, detail: str) -> None:
    STATE_FILE.write_text(
        json.dumps({"state": state, "detail": detail, "max_speed": current_speed()}, indent=2) + "\n",
        encoding="utf-8",
    )


def read_state() -> dict[str, object]:
    if not STATE_FILE.exists():
        return {"state": "failed", "detail": "service has not been initialized", "max_speed": None}
    return json.loads(STATE_FILE.read_text(encoding="utf-8"))


def current_speed() -> float | None:
    try:
        return read_max_speed(CONFIG)
    except Exception:
        return None


def initialize() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    NAV_LOG.parent.mkdir(parents=True, exist_ok=True)
    error = config_error(CONFIG)
    if error:
        write_state("failed", error)
        nav_log(f"failed to start: {error}")
    else:
        write_state("healthy", "navigation service is running")
        nav_log("started successfully")
    return 0


def print_status() -> int:
    audit("navigation.service status inspected")
    state = read_state()
    active = "active (running)" if state["state"] == "healthy" else "failed"
    print(f"* navigation.service - Robot navigation service")
    print(f"   Loaded: loaded (/etc/robot/navigation.yaml)")
    print(f"   Active: {active}")
    print(f"   Detail: {state['detail']}")
    return 0 if state["state"] == "healthy" else 3


def print_logs() -> int:
    audit("navigation.service logs inspected")
    if NAV_LOG.exists():
        print(NAV_LOG.read_text(encoding="utf-8"), end="")
    return 0


def validate_command(raw_path: str) -> int:
    path = Path(raw_path)
    audit(f"config validation requested for {path}")
    if not path.exists():
        print(f"invalid: {path} does not exist")
        return 1
    error = config_error(path)
    if error:
        print(f"invalid: {error}")
        return 1
    VALIDATED_FILE.write_text(sha256(path) + "\n", encoding="utf-8")
    print(f"valid: {path}")
    return 0


def restart() -> int:
    audit("navigation.service restart requested")
    errors = [error for error in [config_error(CONFIG), ownership_error(CONFIG), validation_error()] if error]
    if errors:
        detail = "; ".join(errors)
        write_state("failed", detail)
        nav_log(f"restart blocked: {detail}")
        print(f"navigation.service failed: {detail}", flush=True)
        return 1
    write_state("healthy", "navigation service is running")
    nav_log("restarted successfully with validated configuration")
    REPORT.write_text(
        "mission: restore navigation service\n"
        "robot: robot-01\n"
        "navigation: healthy\n"
        f"max_speed: {read_max_speed(CONFIG):g}\n",
        encoding="utf-8",
    )
    print("navigation.service restarted")
    return 0


def validation_error() -> str:
    if not VALIDATED_FILE.exists():
        return "candidate configuration was not validated"
    if VALIDATED_FILE.read_text(encoding="utf-8").strip() != sha256(CONFIG):
        return "installed configuration does not match validated candidate"
    return ""


def status_payload() -> dict[str, object]:
    state = read_state()
    return {
        "robot": "robot-01",
        "navigation": state["state"],
        "max_speed": state.get("max_speed"),
    }


def print_state_json() -> int:
    print(json.dumps(status_payload(), indent=2))
    return 0
