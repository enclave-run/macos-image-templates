#!/bin/bash

set -euo pipefail

install_root=/usr/local/libexec/enclave
sudo install -d -o root -g wheel -m 0755 "$install_root"
sudo install -d -o root -g wheel -m 0700 /var/db/enclave
# Fence bootstrap by the current boot session. The final image deliberately
# retains this sentinel: a cloned runtime gets a new kern.bootsessionuuid, at
# which point bootstrap removes the expired sentinel and seals the guest.
build_boot_session=$(/usr/sbin/sysctl -n kern.bootsessionuuid)
if [[ ! "$build_boot_session" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]]; then
  echo "invalid kern.bootsessionuuid: $build_boot_session" >&2
  exit 66
fi
umask 077
printf '%s\n' "$build_boot_session" > /tmp/enclave-image-build-sentinel
sudo install -o root -g wheel -m 0600 \
  /tmp/enclave-image-build-sentinel \
  /var/db/enclave/image-build-in-progress
rm -f /tmp/enclave-image-build-sentinel

# A source image may contain an older job. Keep the job absent for the whole
# bake, then publish the staged plist only as the final Xcode-image operation.
sudo launchctl bootout system/com.enclave.guest-bootstrap >/dev/null 2>&1 || true
sudo rm -f /Library/LaunchDaemons/com.enclave.guest-bootstrap.plist
install -d -m 0700 /Users/admin/Library/Logs/Enclave

verify_sha256() {
  local path=$1
  local expected=$2
  local label=$3

  if [[ ! "$expected" =~ ^[a-f0-9]{64}$ ]]; then
    echo "missing or malformed expected SHA-256 for $label" >&2
    exit 64
  fi
  local actual
  actual=$(shasum -a 256 "$path" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "$label SHA-256 mismatch: expected $expected, got $actual" >&2
    exit 65
  fi
}

if [[ "${INSTALL_SBXD:-0}" != "1" || "${INSTALL_BOOTSTRAP:-0}" != "1" ]]; then
  echo "owned images require both sbxd-darwin and guest bootstrap artifacts" >&2
  exit 64
fi

verify_sha256 /tmp/enclave-upload-sbxd-darwin "$SBXD_SHA256" "sbxd-darwin upload"
sudo rm -f "$install_root/sbxd-darwin"
sudo install -o root -g wheel -m 0755 \
  /tmp/enclave-upload-sbxd-darwin \
  "$install_root/sbxd-darwin"
verify_sha256 "$install_root/sbxd-darwin" "$SBXD_SHA256" "sbxd-darwin install"
sudo install -o root -g wheel -m 0644 \
  /tmp/com.enclave.sbxd-darwin.plist \
  /Library/LaunchAgents/com.enclave.sbxd-darwin.plist

verify_sha256 \
  /tmp/enclave-upload-guest-bootstrap \
  "$GUEST_BOOTSTRAP_SHA256" \
  "guest bootstrap upload"
sudo rm -f "$install_root/enclave-guest-bootstrap"
sudo install -o root -g wheel -m 0755 \
  /tmp/enclave-upload-guest-bootstrap \
  "$install_root/enclave-guest-bootstrap"
verify_sha256 \
  "$install_root/enclave-guest-bootstrap" \
  "$GUEST_BOOTSTRAP_SHA256" \
  "guest bootstrap install"
sudo install -o root -g wheel -m 0644 \
  /tmp/com.enclave.guest-bootstrap.plist \
  "$install_root/com.enclave.guest-bootstrap.plist"

printf 'installed sbxd-darwin sha256=%s\n' "$SBXD_SHA256"
printf 'installed guest-bootstrap sha256=%s\n' "$GUEST_BOOTSTRAP_SHA256"

rm -f \
  /tmp/enclave-upload-sbxd-darwin \
  /tmp/enclave-upload-guest-bootstrap \
  /tmp/com.enclave.sbxd-darwin.plist \
  /tmp/com.enclave.guest-bootstrap.plist
