#!/usr/bin/env bash
# 01-baseline.sh — agents + hardening common to every DataApps instance.
set -euxo pipefail

# --- Required tooling/agents -------------------------------------------------
# SSM agent ships preinstalled on AL2023; make sure it's current & enabled.
dnf -y install amazon-ssm-agent || true
systemctl enable amazon-ssm-agent

# CloudWatch agent (config delivered later via SSM Parameter Store / Ansible)
dnf -y install amazon-cloudwatch-agent

# Common utilities every role expects
dnf -y install jq tar unzip git chrony python3 python3-pip

# Time sync (Amazon Time Sync Service is default in chrony on AL2023; assert enabled)
systemctl enable chronyd

# --- Hardening baseline -------------------------------------------------------
# SSH: key/SSM only
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Sensible default file limits for JVM/data apps (roles may raise further)
cat > /etc/security/limits.d/90-dataapps.conf << 'LIM'
*  soft  nofile  65536
*  hard  nofile  65536
LIM

# Disable kernel modules we never want on these hosts
cat > /etc/modprobe.d/dataapps-blacklist.conf << 'MOD'
install dccp /bin/true
install sctp /bin/true
MOD

echo "OK: baseline agents + hardening applied"
