#!/usr/bin/env bash
#
# Prepares a fresh Ubuntu VPS (24.04 or 26.04) to run BLML. Run it once, as
# root, on the
# new server:
#
#   ssh root@<vps-ip> 'bash -s' < provision-vps.sh
#
# It installs Docker, opens exactly the ports BLML needs, and hardens SSH.
# It does NOT deploy the app — see DEPLOY.md for the rest.
#
# Safe to re-run: every step checks before acting.
set -euo pipefail

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

log "System packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg ufw fail2ban unattended-upgrades

log "Docker"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
else
  echo "  already installed: $(docker --version)"
fi

log "Unattended security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

log "Firewall"
# Default deny inbound. Everything BLML needs is listed explicitly; the app
# itself (6060) is deliberately absent because Caddy fronts it and the admin
# dashboard is reached through an SSH tunnel, not over the network.
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp    comment 'ssh'      >/dev/null
ufw allow 80/tcp    comment 'http/acme' >/dev/null
ufw allow 443/tcp   comment 'https'    >/dev/null
ufw allow 3478/udp  comment 'turn'     >/dev/null
ufw allow 3478/tcp  comment 'turn'     >/dev/null
# Must match min-port/max-port in the generated turnserver.conf.
ufw allow 49160:49200/udp comment 'turn relay' >/dev/null
ufw --force enable >/dev/null
ufw status numbered

log "SSH hardening"
# Only touched if key-based login already works, so this cannot lock you out of
# a box you are still reaching with a password.
if [ -s /root/.ssh/authorized_keys ]; then
  sed -i \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' \
    /etc/ssh/sshd_config
  # sshd takes the FIRST occurrence of a keyword, and sshd_config Includes the
  # drop-in directory near the top, reading it in alphabetical order. Cloud
  # images ship 50-cloud-init.conf with "PasswordAuthentication yes", so a
  # 99- file is silently dead: it is read after cloud-init's and ignored.
  # Sort ahead of everything instead.
  mkdir -p /etc/ssh/sshd_config.d
  rm -f /etc/ssh/sshd_config.d/99-blml.conf
  printf 'PasswordAuthentication no\nPermitRootLogin prohibit-password\nKbdInteractiveAuthentication no\n' \
    > /etc/ssh/sshd_config.d/00-blml.conf
  systemctl reload ssh 2>/dev/null || systemctl reload sshd

  # Verify against the effective config rather than trusting the write. This
  # check is the whole point: the previous version reported success while
  # password login was still wide open.
  eff=$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')
  if [ "$eff" = "no" ]; then
    echo "  password login disabled (verified: sshd -T reports no)"
  else
    warn "password login is STILL ENABLED (sshd -T says '$eff')."
    warn "Check for another drop-in in /etc/ssh/sshd_config.d/ that sorts before 00-blml.conf."
    exit 1
  fi
else
  warn "no /root/.ssh/authorized_keys — leaving password login ENABLED."
  warn "Add your key, then re-run this script to disable it."
fi

log "Swap"
# The smaller Vultr plans have no swap. Postgres is happier with a little.
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "  2G swapfile active"
else
  echo "  already present"
fi

log "Done"
cat <<'EOF'
Next, from your Mac:
  1. Point chat.blml.app at this server's IP (A record)
  2. ./deploy/migrate-to-vps.sh root@<vps-ip>     # ships code, secrets and data
See deploy/DEPLOY.md for the full runbook.
EOF
