#!/usr/bin/env bash
# 00-os-update.sh — bring the latest-AL2023 base fully current FIRST,
# then the patch policy (02) locks/strips from this known state.
set -euxo pipefail

# AL2023: dnf is the package manager ('yum' is just an alias). Use dnf explicitly.
dnf -y clean all

# Show which AL2023 release/repos we're updating against (build log evidence)
cat /etc/os-release
dnf releasever 2>/dev/null || rpm -q system-release || true

# Full update of the pristine base image
dnf -y update

# Record the post-update package set BEFORE policy is applied (audit artifact)
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/pkglist-post-update.txt
echo "OK: base OS updated; $(wc -l < /tmp/pkglist-post-update.txt) packages installed"
