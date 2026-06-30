#!/bin/sh
set -eu

role="${LAB_ROLE:?missing LAB_ROLE}"
user="${LAB_USER:?missing LAB_USER}"
password="${LAB_PASSWORD:?missing LAB_PASSWORD}"

mkdir -p /run/sshd /etc/ssh
install -m 0600 /lab/host_keys/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
install -m 0644 /lab/host_keys/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub

if ! getent group robot >/dev/null; then
    groupadd robot
fi

if ! id "$user" >/dev/null 2>&1; then
    if getent group "$user" >/dev/null; then
        useradd -m -s /bin/bash -g "$user" "$user"
    else
        useradd -m -s /bin/bash "$user"
    fi
fi
echo "$user:$password" | chpasswd
mkdir -p "/home/$user/.ssh"
chown "$user:$user" "/home/$user/.ssh"
chmod 0700 "/home/$user/.ssh"

cat >/etc/ssh/sshd_config <<EOF
Port 22
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_ed25519_key
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
UsePAM no
PermitRootLogin no
AllowTcpForwarding yes
GatewayPorts no
X11Forwarding no
PrintMotd no
Subsystem sftp /usr/lib/openssh/sftp-server
AllowUsers $user
EOF

if [ "$role" = "robot" ]; then
    usermod -a -G robot "$user"
    mkdir -p /etc/robot /opt/field-lab/state /var/log/robot
    install -o root -g robot -m 0640 /lab/robot/navigation.broken.yaml /etc/robot/navigation.yaml
    chown -R root:robot /opt/field-lab /var/log/robot
    chmod 0775 /opt/field-lab/state /var/log/robot
    cat >/etc/sudoers.d/field-lab-robot <<'EOF'
operator ALL=(root) NOPASSWD: /usr/bin/install -o root -g robot -m 0640 /tmp/navigation.yaml /etc/robot/navigation.yaml
operator ALL=(root) NOPASSWD: /usr/local/bin/systemctl --user restart navigation.service
EOF
    chmod 0440 /etc/sudoers.d/field-lab-robot
    robot-service initialize
    robot-diagnostic-server &
fi

exec /usr/sbin/sshd -D -e
