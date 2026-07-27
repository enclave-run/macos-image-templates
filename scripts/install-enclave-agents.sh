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

if [[ "${INSTALL_SBXD:-0}" == "1" ]]; then
  sudo install -o root -g wheel -m 0755 /tmp/sbxd-darwin "$install_root/sbxd-darwin"
  sudo install -o root -g wheel -m 0644 \
    /tmp/com.enclave.sbxd-darwin.plist \
    /Library/LaunchAgents/com.enclave.sbxd-darwin.plist
fi

if [[ "${INSTALL_BOOTSTRAP:-0}" == "1" ]]; then
  sudo install -o root -g wheel -m 0755 \
    /tmp/enclave-guest-bootstrap \
    "$install_root/enclave-guest-bootstrap"
  sudo install -o root -g wheel -m 0644 \
    /tmp/com.enclave.guest-bootstrap.plist \
    /Library/LaunchDaemons/com.enclave.guest-bootstrap.plist
fi

rm -f \
  /tmp/sbxd-darwin \
  /tmp/enclave-guest-bootstrap \
  /tmp/com.enclave.sbxd-darwin.plist \
  /tmp/com.enclave.guest-bootstrap.plist
