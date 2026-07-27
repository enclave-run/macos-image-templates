#!/bin/bash

set -euo pipefail

install_root=/usr/local/libexec/enclave
sudo install -d -o root -g wheel -m 0755 "$install_root"

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

if [[ "${INSTALL_MACOS_UI:-0}" == "1" ]]; then
  sudo install -o root -g wheel -m 0755 \
    /tmp/enclave-macos-ui \
    "$install_root/enclave-macos-ui"
fi

rm -f \
  /tmp/sbxd-darwin \
  /tmp/enclave-guest-bootstrap \
  /tmp/enclave-macos-ui \
  /tmp/com.enclave.sbxd-darwin.plist \
  /tmp/com.enclave.guest-bootstrap.plist
