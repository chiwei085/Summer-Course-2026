# SSH Field Operations Lab

This lab is a small remote operations mission. You will restore a robot navigation
service through SSH instead of answering quiz prompts.

The runtime creates two Docker nodes:

```text
student workstation -> field-gateway -> robot-01
```

Only the gateway is reachable from your workstation. The robot is on a private
Docker network, and its diagnostic web service listens only on the robot's
`127.0.0.1:8080`.

## Requirements

- Python 3
- Docker
- Docker Compose
- OpenSSH client tools: `ssh`, `ssh-keygen`, `ssh-copy-id`
- `rsync`

## Start

```bash
python3 labctl.py start
```

Keep this directory as your working directory for the mission. Use another
terminal for the SSH commands.

Mission Control prints the trusted host fingerprints. Compare them with the
fingerprints shown by SSH before accepting a new host.

Bootstrap credentials:

```text
gateway: field@127.0.0.1:2222  password field-lab
robot:   operator@robot-01      password robot-lab
```

## Mission

Create a lab key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/rvl_field_lab
```

First connect to the gateway and verify the fingerprint:

```bash
ssh -p 2222 field@127.0.0.1
```

Install your key on the gateway:

```bash
ssh-copy-id -i ~/.ssh/rvl_field_lab.pub -p 2222 field@127.0.0.1
```

Add these aliases to `~/.ssh/config`:

This lab intentionally uses your real SSH config so the aliases behave like
normal operational infrastructure. If you already use `field-gateway` or
`robot-01` for another machine, move that entry aside before the lab and restore
it afterward.

```sshconfig
Host field-gateway
    HostName 127.0.0.1
    Port 2222
    User field
    IdentityFile ~/.ssh/rvl_field_lab

Host robot-01
    HostName robot-01
    User operator
    ProxyJump field-gateway
    IdentityFile ~/.ssh/rvl_field_lab
```

Install your key on the robot through the gateway:

```bash
ssh-copy-id -i ~/.ssh/rvl_field_lab.pub robot-01
```

Confirm that direct robot access works through the alias:

```bash
ssh robot-01
```

Diagnose the failed navigation service on the robot:

```bash
systemctl --user status navigation.service
journalctl --user -u navigation.service --no-pager
```

Upload and validate the fixed configuration:

```bash
rsync -av deployment/navigation.yaml robot-01:/tmp/navigation.yaml
ssh robot-01 robot-config-check /tmp/navigation.yaml
```

Install the validated config and restart the service:

```bash
ssh robot-01 'sudo install -o root -g robot -m 0640 /tmp/navigation.yaml /etc/robot/navigation.yaml'
ssh robot-01 'sudo systemctl --user restart navigation.service'
```

Open a local tunnel to the robot-only diagnostic page:

```bash
ssh -N -L 8080:127.0.0.1:8080 robot-01
```

If local port `8080` is already in use, choose another local port, for example:

```bash
ssh -N -L 18080:127.0.0.1:8080 robot-01
curl http://127.0.0.1:18080/status
```

In another terminal:

```bash
curl http://127.0.0.1:8080/status
```

Retrieve the mission report:

```bash
rsync -av robot-01:/var/log/robot/mission-report.txt .
```

## Mission Control

Run these from the lab directory:

```bash
python3 labctl.py mission
python3 labctl.py status
```

Mission Control reads runtime state, SSH resolution, audit logs, service status,
and the downloaded report. It does not edit your `~/.ssh/config`,
`known_hosts`, or key files.

## Reset

```bash
python3 labctl.py reset
```

This recreates the Docker runtime. It does not remove your local SSH key,
`~/.ssh/config`, or `mission-report.txt`.

To stop or remove lab containers:

```bash
python3 labctl.py stop
python3 labctl.py clean
```

The checked-in SSH host keys are fixed lab fixtures for repeatable teaching.
Do not reuse them for any real machine.

Inside the robot container, `systemctl` and `journalctl` are lab wrappers around
a lightweight service model. The command shape is intentional for practice, but
`sudo systemctl --user ...` is not a production systemd pattern.
