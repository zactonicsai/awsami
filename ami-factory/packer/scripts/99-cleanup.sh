#!/usr/bin/env bash
# 99-cleanup.sh — make the image generic & small. Runs LAST.
set -euxo pipefail

# Preserve audit artifacts produced by earlier scripts onto the image
mkdir -p /var/lib/dataapps-ami
cp -f /tmp/pkglist-*.txt /var/lib/dataapps-ami/ 2>/dev/null || true
cp -rf /tmp/patch-policy /var/lib/dataapps-ami/applied-policy 2>/dev/null || true

# Package cache
dnf -y clean all
rm -rf /var/cache/dnf

# cloud-init: forget this instance so the NEXT boot runs first-boot again
cloud-init clean --logs || true

# Machine identity must be regenerated per instance
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# SSH host keys must NOT be shared across instances (regenerated on boot)
rm -f /etc/ssh/ssh_host_*

# Logs, temp, histories
find /var/log -type f -exec truncate -s 0 {} \; || true
rm -rf /tmp/* /var/tmp/* || true
rm -f /root/.bash_history /home/ec2-user/.bash_history || true
export HISTSIZE=0

# Remove authorized_keys injected for the Packer build session
rm -f /root/.ssh/authorized_keys /home/ec2-user/.ssh/authorized_keys || true

sync
echo "OK: image cleaned"
