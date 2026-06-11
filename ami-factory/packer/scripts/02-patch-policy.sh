#!/usr/bin/env bash
# =============================================================================
# 02-patch-policy.sh — Enforce the org patch policy on the image:
#   Layer 1: REMOVE denied packages, then FAIL CLOSED if any remain
#   Layer 2: VERSIONLOCK approved-pinned packages (dnf can't move them)
#   Layer 3: EXCLUDE packages from all future 'dnf update' on the host
# Inputs (shipped by Packer file provisioner to /tmp/patch-policy/):
#   denied-packages.txt        one package name per line; MUST NOT be installed
#   approved-lock.txt          NAME-VERSION-RELEASE.ARCH lines to versionlock
#   excluded-from-update.txt   glob patterns appended to dnf.conf excludepkgs
# Lines starting with # and blank lines are ignored in all three files.
# =============================================================================
set -euxo pipefail

POLICY_DIR="/tmp/patch-policy"
strip() { grep -vE '^\s*(#|$)' "$1" 2>/dev/null || true; }

# -----------------------------------------------------------------------------
# Layer 1 — Denied packages: remove, then verify none survive (FAIL-CLOSED)
# -----------------------------------------------------------------------------
DENIED_FILE="$POLICY_DIR/denied-packages.txt"
if [[ -s "$DENIED_FILE" ]]; then
  mapfile -t DENIED < <(strip "$DENIED_FILE")
  if ((${#DENIED[@]})); then
    # Remove if present (ignore "not installed" — that's the goal state)
    dnf -y remove "${DENIED[@]}" || true

    # Verify: any denied package still installed => HARD FAIL the AMI build
    FAILED=0
    for p in "${DENIED[@]}"; do
      if rpm -q "$p" &>/dev/null; then
        echo "POLICY VIOLATION: denied package still installed: $p" >&2
        FAILED=1
      fi
    done
    if ((FAILED)); then
      echo "FATAL: denied packages present after removal — failing build (fail-closed)" >&2
      exit 1
    fi
    # Belt & braces: also exclude denied names so nothing reinstalls them later
    printf '%s\n' "${DENIED[@]}" >> /tmp/.policy-extra-excludes
  fi
fi

# -----------------------------------------------------------------------------
# Layer 2 — Approved pins: dnf versionlock (plugin) freezes exact NVRs
# -----------------------------------------------------------------------------
APPROVED_FILE="$POLICY_DIR/approved-lock.txt"
if [[ -s "$APPROVED_FILE" ]] && strip "$APPROVED_FILE" | grep -q .; then
  dnf -y install python3-dnf-plugin-versionlock

  while IFS= read -r nvr; do
    # If the exact NVR isn't installed, try to install it (downgrade/upgrade to pin)
    if ! rpm -q "$nvr" &>/dev/null; then
      dnf -y install "$nvr" || {
        echo "FATAL: approved pin not installable: $nvr (not in repos?)" >&2
        exit 1
      }
    fi
    dnf versionlock add "$nvr"
  done < <(strip "$APPROVED_FILE")

  echo "--- versionlock list ---"
  dnf versionlock list
fi

# -----------------------------------------------------------------------------
# Layer 3 — Update exclusions: host-level 'never update these' patterns
# -----------------------------------------------------------------------------
EXCLUDE_FILE="$POLICY_DIR/excluded-from-update.txt"
{ strip "$EXCLUDE_FILE"; cat /tmp/.policy-extra-excludes 2>/dev/null; } \
  | sort -u > /tmp/.policy-all-excludes || true

if [[ -s /tmp/.policy-all-excludes ]]; then
  EXCLUDES=$(paste -sd' ' /tmp/.policy-all-excludes)
  # Append (or replace) excludepkgs in the [main] section of dnf.conf
  if grep -q '^excludepkgs=' /etc/dnf/dnf.conf; then
    sed -i "s|^excludepkgs=.*|excludepkgs=${EXCLUDES}|" /etc/dnf/dnf.conf
  else
    printf 'excludepkgs=%s\n' "$EXCLUDES" >> /etc/dnf/dnf.conf
  fi
  echo "--- /etc/dnf/dnf.conf ---"; cat /etc/dnf/dnf.conf
fi

# -----------------------------------------------------------------------------
# Determinism note (AL2023): the image's repo URLs are locked to the releasever
# baked in /etc/dnf/vars/releasever — record it so two builds on the same base
# resolve the same package universe. Bump deliberately via 'dnf upgrade --releasever'.
# -----------------------------------------------------------------------------
echo "AL2023 locked releasever: $(cat /etc/dnf/vars/releasever 2>/dev/null || echo 'latest')"

# Final audit artifact: package set AFTER policy applied
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/pkglist-post-policy.txt
diff /tmp/pkglist-post-update.txt /tmp/pkglist-post-policy.txt > /tmp/pkglist-policy-diff.txt || true
echo "OK: patch policy enforced (diff lines: $(wc -l < /tmp/pkglist-policy-diff.txt))"
