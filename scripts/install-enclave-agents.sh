#!/bin/bash

set -euo pipefail

install_root=/usr/local/libexec/enclave
sudo install -d -o root -g wheel -m 0755 "$install_root"
sudo install -d -o root -g wheel -m 0700 /var/db/enclave
# launchd can discover a newly installed plist asynchronously. Keep bootstrap
# inert for the remainder of the bake; the final layer removes this sentinel
# only after image acceptance has completed.
sudo install -o root -g wheel -m 0600 \
  /dev/null \
  /var/db/enclave/image-build-in-progress
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
  /Library/LaunchDaemons/com.enclave.guest-bootstrap.plist

printf 'installed sbxd-darwin sha256=%s\n' "$SBXD_SHA256"
printf 'installed guest-bootstrap sha256=%s\n' "$GUEST_BOOTSTRAP_SHA256"

rm -f \
  /tmp/enclave-upload-sbxd-darwin \
  /tmp/enclave-upload-guest-bootstrap \
  /tmp/com.enclave.sbxd-darwin.plist \
  /tmp/com.enclave.guest-bootstrap.plist
