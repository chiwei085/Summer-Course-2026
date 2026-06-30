#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pty
import select
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent
COMPOSE_FILE = ROOT / "compose.yaml"
PROJECT = "ssh-field-lab"
GATEWAY_PORT = 2222
DIAGNOSTIC_TUNNEL_PORT = 18080
DEFAULT_KEY = Path.home() / ".ssh" / "rvl_field_lab"
DEFAULT_REPORT = ROOT / "mission-report.txt"
GATEWAY_PASSWORD = "field-lab"
ROBOT_PASSWORD = "robot-lab"
ROBOT_HOST = "robot-01"
NAVIGATION_SERVICE = "navigation.service"
CANDIDATE_CONFIG = "/tmp/navigation.yaml"
INSTALLED_CONFIG = "/etc/robot/navigation.yaml"
REMOTE_REPORT = "/var/log/robot/mission-report.txt"


@dataclass
class CommandResult:
    args: list[str]
    returncode: int
    stdout: str
    stderr: str


@dataclass
class CheckResult:
    name: str
    passed: bool
    detail: str = ""


@dataclass
class LabContext:
    ssh_config: Path | None = None
    known_hosts: Path | None = None
    identity_file: Path | None = None
    report_path: Path = DEFAULT_REPORT


def run(args: list[str], cwd: Path = ROOT, check: bool = False, env: dict[str, str] | None = None) -> CommandResult:
    merged_env = os.environ.copy()
    merged_env.update({"LC_ALL": "C", "LANG": "C"})
    if env:
        merged_env.update(env)
    result = subprocess.run(
        args,
        cwd=cwd,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    wrapped = CommandResult(args, result.returncode, result.stdout, result.stderr)
    if check and wrapped.returncode != 0:
        raise RuntimeError(command_output(wrapped))
    return wrapped


def command_output(result: CommandResult) -> str:
    output = [f"$ {' '.join(result.args)}"]
    if result.stdout:
        output.append(result.stdout.rstrip())
    if result.stderr:
        output.append(result.stderr.rstrip())
    return "\n".join(output)


def compose(args: list[str], check: bool = False) -> CommandResult:
    return run(["docker", "compose", "-f", str(COMPOSE_FILE), "-p", PROJECT, *args], check=check)


def compose_exec(service: str, args: list[str], check: bool = False) -> CommandResult:
    return compose(["exec", "-T", service, *args], check=check)


def service_running(service: str) -> bool:
    result = compose(["ps", "--status", "running", "--services"])
    return service in result.stdout.splitlines()


def wait_for_gateway(timeout: float = 30.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if port_open("127.0.0.1", GATEWAY_PORT):
            scan = run(["ssh-keyscan", "-p", str(GATEWAY_PORT), "127.0.0.1"])
            if scan.returncode == 0 and "ssh-ed25519" in scan.stdout:
                return
        time.sleep(0.5)
    raise RuntimeError("gateway SSH endpoint did not become reachable")


def host_fingerprint(name: str) -> str:
    pubkey = ROOT / "fixtures" / "host_keys" / name / "ssh_host_ed25519_key.pub"
    result = run(["ssh-keygen", "-l", "-f", str(pubkey)], check=True)
    return result.stdout.split()[1]


def print_field_info() -> None:
    print()
    print("Trusted field information")
    print("-------------------------")
    print(f"Gateway endpoint: 127.0.0.1:{GATEWAY_PORT}")
    print(f"Gateway user:     field")
    print(f"Gateway password: {GATEWAY_PASSWORD}")
    print(f"Gateway key:      {host_fingerprint('gateway')}")
    print()
    print(f"Robot endpoint:   {ROBOT_HOST}, reachable only through field-gateway")
    print("Robot user:       operator")
    print(f"Robot password:   {ROBOT_PASSWORD}")
    print(f"Robot key:        {host_fingerprint('robot')}")
    print()


def ssh_options(context: LabContext) -> list[str]:
    options: list[str] = []
    if context.ssh_config:
        options.extend(["-F", str(context.ssh_config)])
    if context.known_hosts:
        options.extend(["-o", f"UserKnownHostsFile={context.known_hosts}"])
    return options


def ssh_command(context: LabContext, host: str, remote: list[str], batch: bool = True) -> list[str]:
    args = ["ssh", *ssh_options(context)]
    if batch:
        args.extend(["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"])
    args.extend([host, *remote])
    return args


def rsync_command(context: LabContext, source: str, target: str) -> list[str]:
    ssh_transport = shlex.join(["ssh", *ssh_options(context)])
    return ["rsync", "-av", "-e", ssh_transport, source, target]


def parse_ssh_g(context: LabContext, host: str) -> dict[str, list[str]]:
    result = run(["ssh", *ssh_options(context), "-G", host])
    values: dict[str, list[str]] = {}
    if result.returncode != 0:
        return values
    for line in result.stdout.splitlines():
        key, _, value = line.partition(" ")
        values.setdefault(key, []).append(value)
    return values


def known_host_has_fingerprint(context: LabContext, host: str, fingerprint: str) -> bool:
    known_hosts = context.known_hosts or (Path.home() / ".ssh" / "known_hosts")
    if not known_hosts.exists():
        return False
    result = run(["ssh-keygen", "-F", host, "-f", str(known_hosts), "-l"])
    return result.returncode == 0 and fingerprint in result.stdout


def batch_ssh_ok(context: LabContext, host: str) -> bool:
    return run(ssh_command(context, host, ["true"])).returncode == 0


def docker_text(service: str, args: list[str]) -> str:
    result = compose_exec(service, args)
    return result.stdout.strip() if result.returncode == 0 else ""


def audit_contains(*needles: str) -> bool:
    text = docker_text(ROBOT_HOST, ["sh", "-lc", "cat /opt/field-lab/state/audit.log 2>/dev/null || true"])
    return all(needle in text for needle in needles)


def local_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def remote_sha256(path: str) -> str:
    result = compose_exec(ROBOT_HOST, ["sha256sum", path])
    if result.returncode != 0:
        return ""
    return result.stdout.split()[0]


def installed_config_ok() -> CheckResult:
    expected_hash = local_sha256(ROOT / "deployment" / "navigation.yaml")
    actual_hash = remote_sha256(INSTALLED_CONFIG)
    stat_result = compose_exec(ROBOT_HOST, ["stat", "-c", "%U:%G %a", INSTALLED_CONFIG])
    ownership = stat_result.stdout.strip()
    passed = actual_hash == expected_hash and ownership == "root:robot 640"
    detail = ""
    if not passed:
        detail = f"sha256={actual_hash or '<missing>'}, expected={expected_hash}; {ownership or '<missing stat>'}"
    return CheckResult("Installed config content, owner, group, and mode", passed, detail)


def navigation_healthy() -> bool:
    result = compose_exec(ROBOT_HOST, ["robot-service", "state-json"])
    if result.returncode != 0:
        return False
    try:
        return json.loads(result.stdout).get("navigation") == "healthy"
    except json.JSONDecodeError:
        return False


def check_config(context: LabContext) -> list[CheckResult]:
    gateway = parse_ssh_g(context, "field-gateway")
    robot = parse_ssh_g(context, ROBOT_HOST)

    def value(values: dict[str, list[str]], key: str) -> str:
        return values.get(key, [""])[0]

    def identities(values: dict[str, list[str]]) -> list[str]:
        return values.get("identityfile", [])

    expected_key = str(context.identity_file or DEFAULT_KEY)
    gateway_ok = (
        value(gateway, "hostname") == "127.0.0.1"
        and value(gateway, "port") == str(GATEWAY_PORT)
        and value(gateway, "user") == "field"
        and any(path.endswith("rvl_field_lab") or path == expected_key for path in identities(gateway))
    )
    robot_ok = (
        value(robot, "hostname") == ROBOT_HOST
        and value(robot, "user") == "operator"
        and value(robot, "proxyjump") == "field-gateway"
        and any(path.endswith("rvl_field_lab") or path == expected_key for path in identities(robot))
    )
    return [
        CheckResult("SSH config alias field-gateway resolves correctly", gateway_ok),
        CheckResult("SSH config alias robot-01 resolves through ProxyJump", robot_ok),
    ]


def collect_checks(context: LabContext) -> list[CheckResult]:
    checks = [
        CheckResult("Gateway container is running", service_running("field-gateway")),
        CheckResult("Robot container is running", service_running(ROBOT_HOST)),
        CheckResult("Gateway endpoint is reachable", port_open("127.0.0.1", GATEWAY_PORT)),
        CheckResult(
            "Gateway host key accepted with trusted fingerprint",
            known_host_has_fingerprint(context, f"[127.0.0.1]:{GATEWAY_PORT}", host_fingerprint("gateway")),
        ),
        CheckResult(
            "Robot host key accepted with trusted fingerprint",
            known_host_has_fingerprint(context, ROBOT_HOST, host_fingerprint("robot")),
        ),
        *check_config(context),
        CheckResult("Public-key login works for field-gateway", batch_ssh_ok(context, "field-gateway")),
        CheckResult("Public-key login works for robot-01", batch_ssh_ok(context, ROBOT_HOST)),
        CheckResult(
            "Navigation status and logs were inspected",
            audit_contains(f"{NAVIGATION_SERVICE} status inspected", f"{NAVIGATION_SERVICE} logs inspected"),
        ),
        CheckResult(
            f"Candidate config uploaded to {CANDIDATE_CONFIG}",
            compose_exec(ROBOT_HOST, ["test", "-f", CANDIDATE_CONFIG]).returncode == 0,
        ),
        CheckResult("Candidate config was validated", audit_contains("config validation requested")),
        installed_config_ok(),
        CheckResult("Navigation service is healthy", navigation_healthy()),
        CheckResult("Diagnostic endpoint was reached through an SSH tunnel", audit_contains("diagnostic status fetched")),
        mission_report_check(context),
    ]
    return checks


def mission_report_check(context: LabContext) -> CheckResult:
    if not context.report_path.exists():
        return CheckResult("Mission report was downloaded", False)
    text = context.report_path.read_text(encoding="utf-8", errors="replace")
    expected = ["mission: restore navigation service", f"robot: {ROBOT_HOST}", "navigation: healthy", "max_speed: 1.2"]
    missing = [line for line in expected if line not in text]
    return CheckResult("Mission report was downloaded with healthy result", not missing, "missing: " + ", ".join(missing) if missing else "")


def port_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1.0):
            return True
    except OSError:
        return False


def print_checks(checks: list[CheckResult]) -> None:
    for check in checks:
        marker = "[x]" if check.passed else "[ ]"
        print(f"{marker} {check.name}")
        if check.detail and not check.passed:
            print(f"    {check.detail}")


def mission(context: LabContext) -> None:
    print("SSH Field Operations Lab")
    print("========================")
    print()
    print("Topology")
    print("--------")
    print(f"workstation -> field-gateway -> {ROBOT_HOST}")
    print()
    print_field_info()
    print("Mission progress")
    print("----------------")
    print_checks(collect_checks(context))


def status(context: LabContext) -> int:
    checks = collect_checks(context)
    print_checks(checks)
    return 0 if all(check.passed for check in checks) else 1


def start() -> None:
    compose(["up", "--build", "-d"], check=True)
    wait_for_gateway()
    print_field_info()
    mission(LabContext())


def reset() -> None:
    compose(["down", "--volumes", "--remove-orphans"], check=True)
    compose(["up", "--build", "-d"], check=True)
    wait_for_gateway()
    print("Lab runtime reset.")
    print_field_info()


def stop() -> None:
    compose(["stop"], check=True)
    print("Lab containers stopped.")


def clean() -> None:
    compose(["down", "--volumes", "--remove-orphans", "--rmi", "local"], check=True)
    print("Lab containers and local lab images removed.")


def run_with_password(args: list[str], passwords: list[str], timeout: float = 40.0) -> str:
    output = bytearray()
    password_index = 0
    accepted_hosts = 0
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(args[0], args)

    deadline = time.monotonic() + timeout
    try:
        while True:
            if time.monotonic() > deadline:
                os.kill(pid, signal.SIGTERM)
                raise RuntimeError(f"timed out waiting for {' '.join(args)}\n{output.decode(errors='replace')}")
            ready, _, _ = select.select([fd], [], [], 0.2)
            if fd not in ready:
                pid_done, status = os.waitpid(pid, os.WNOHANG)
                if pid_done:
                    if os.waitstatus_to_exitcode(status) != 0:
                        raise RuntimeError(output.decode(errors="replace"))
                    return output.decode(errors="replace")
                continue
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                chunk = b""
            if not chunk:
                _, status = os.waitpid(pid, 0)
                if os.waitstatus_to_exitcode(status) != 0:
                    raise RuntimeError(output.decode(errors="replace"))
                return output.decode(errors="replace")
            output.extend(chunk)
            lower = output.lower()
            lower_chunk = chunk.lower()
            if b"are you sure you want to continue connecting" in lower and accepted_hosts < 4:
                os.write(fd, b"yes\n")
                accepted_hosts += 1
                output.clear()
                continue
            if b"password" in lower_chunk and password_index < len(passwords):
                os.write(fd, (passwords[password_index] + "\n").encode("utf-8"))
                password_index += 1
                output.clear()
    finally:
        try:
            os.close(fd)
        except OSError:
            pass


def write_verify_config(path: Path, key: Path, known_hosts: Path) -> None:
    path.write_text(
        f"""Host field-gateway
    HostName 127.0.0.1
    Port {GATEWAY_PORT}
    User field
    IdentityFile {key}
    UserKnownHostsFile {known_hosts}

Host {ROBOT_HOST}
    HostName {ROBOT_HOST}
    User operator
    ProxyJump field-gateway
    IdentityFile {key}
    UserKnownHostsFile {known_hosts}
""",
        encoding="utf-8",
    )
    path.chmod(0o600)


def inspect_navigation(context: LabContext) -> None:
    run(ssh_command(context, ROBOT_HOST, ["systemctl", "--user", "status", NAVIGATION_SERVICE]), check=False)
    run(ssh_command(context, ROBOT_HOST, ["journalctl", "--user", "-u", NAVIGATION_SERVICE, "--no-pager"]), check=True)


def upload_candidate_config(context: LabContext) -> None:
    run(rsync_command(context, str(ROOT / "deployment" / "navigation.yaml"), f"{ROBOT_HOST}:{CANDIDATE_CONFIG}"), check=True)


def validate_candidate_config(context: LabContext) -> None:
    run(ssh_command(context, ROBOT_HOST, ["robot-config-check", CANDIDATE_CONFIG]), check=True)


def install_navigation_config(context: LabContext) -> None:
    command = ["sudo", "install", "-o", "root", "-g", "robot", "-m", "0640", CANDIDATE_CONFIG, INSTALLED_CONFIG]
    run(ssh_command(context, ROBOT_HOST, command), check=True)


def restart_navigation(context: LabContext) -> None:
    run(ssh_command(context, ROBOT_HOST, ["sudo", "systemctl", "--user", "restart", NAVIGATION_SERVICE]), check=True)


def fetch_diagnostic_status(context: LabContext) -> dict[str, object]:
    tunnel = subprocess.Popen(
        [
            "ssh",
            *ssh_options(context),
            "-N",
            "-L",
            f"{DIAGNOSTIC_TUNNEL_PORT}:127.0.0.1:8080",
            ROBOT_HOST,
        ],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for_port("127.0.0.1", DIAGNOSTIC_TUNNEL_PORT)
        with urllib.request.urlopen(f"http://127.0.0.1:{DIAGNOSTIC_TUNNEL_PORT}/status", timeout=5) as response:
            return json.loads(response.read().decode("utf-8"))
    finally:
        tunnel.terminate()
        try:
            tunnel.wait(timeout=5)
        except subprocess.TimeoutExpired:
            tunnel.kill()


def download_report(context: LabContext) -> None:
    run(rsync_command(context, f"{ROBOT_HOST}:{REMOTE_REPORT}", str(context.report_path)), check=True)


def verify() -> int:
    reset()
    with tempfile.TemporaryDirectory(prefix="ssh-field-lab-") as raw_temp:
        temp = Path(raw_temp)
        ssh_dir = temp / ".ssh"
        ssh_dir.mkdir(mode=0o700)
        key = ssh_dir / "rvl_field_lab"
        known_hosts = ssh_dir / "known_hosts"
        config = ssh_dir / "config"
        report = temp / "mission-report.txt"
        empty_config = ssh_dir / "empty_config"
        empty_config.write_text("", encoding="utf-8")

        run(["ssh-keygen", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
        key.chmod(0o600)

        direct_robot = run(
            [
                "ssh",
                "-F",
                str(empty_config),
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=2",
                f"operator@{ROBOT_HOST}",
                "true",
            ]
        )
        if direct_robot.returncode == 0:
            raise RuntimeError(f"negative check failed: {ROBOT_HOST} was directly reachable from host")

        run_with_password(
            [
                "ssh-copy-id",
                "-i",
                str(key) + ".pub",
                "-p",
                str(GATEWAY_PORT),
                "-o",
                f"UserKnownHostsFile={known_hosts}",
                "-o",
                "StrictHostKeyChecking=accept-new",
                "field@127.0.0.1",
            ],
            [GATEWAY_PASSWORD],
        )
        write_verify_config(config, key, known_hosts)
        run_with_password(
            [
                "ssh-copy-id",
                "-i",
                str(key) + ".pub",
                "-F",
                str(config),
                "-o",
                "StrictHostKeyChecking=accept-new",
                f"operator@{ROBOT_HOST}",
            ],
            [ROBOT_PASSWORD],
        )

        context = LabContext(config, known_hosts, key, report)
        inspect_navigation(context)
        upload_candidate_config(context)
        validate_candidate_config(context)
        install_navigation_config(context)
        restart_navigation(context)

        if compose(["port", ROBOT_HOST, "8080"]).stdout.strip():
            raise RuntimeError("negative check failed: robot diagnostic port is published to host")
        payload = fetch_diagnostic_status(context)
        if payload.get("navigation") != "healthy":
            raise RuntimeError(f"diagnostic endpoint did not report healthy: {payload}")

        download_report(context)
        checks = collect_checks(context)
        print()
        print("Verification checklist")
        print("----------------------")
        print_checks(checks)
        if not all(check.passed for check in checks):
            return 1
        print()
        print("verify: PASS")
        return 0


def wait_for_port(host: str, port: int, timeout: float = 10.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if port_open(host, port):
            return
        time.sleep(0.2)
    raise RuntimeError(f"port did not open: {host}:{port}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Control the SSH Field Operations Lab")
    parser.add_argument("command", choices=["start", "mission", "status", "verify", "reset", "stop", "clean"])
    args = parser.parse_args()

    try:
        if args.command == "start":
            start()
            return 0
        if args.command == "mission":
            mission(LabContext())
            return 0
        if args.command == "status":
            return status(LabContext())
        if args.command == "verify":
            return verify()
        if args.command == "reset":
            reset()
            return 0
        if args.command == "stop":
            stop()
            return 0
        if args.command == "clean":
            clean()
            return 0
    except KeyboardInterrupt:
        print("\nInterrupted.")
        return 130
    except Exception as error:
        print(f"labctl.py: {error}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
