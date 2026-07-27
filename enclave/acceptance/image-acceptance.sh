#!/bin/bash

set -euo pipefail

test "$(uname -m)" = "arm64"
test "$(csrutil status)" = "System Integrity Protection status: enabled."
spctl --status | grep -q 'assessments enabled'
find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print -quit |
  grep -q .
xcodebuild -version
xcodebuild -checkFirstLaunchStatus
xcrun simctl list runtimes
df -k / | awk 'NR == 2 { exit !($2 > 120 * 1024 * 1024) }'
test ! -e /Users/admin/actions-runner
test ! -e /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist
test ! -e /Library/LaunchDaemons/org.cirruslabs.tart-guest-daemon.plist
test ! -e /opt/homebrew/bin/tart-guest-agent
test ! -e /Users/runner
test -x /usr/local/libexec/enclave/sbxd-darwin
test -x /usr/local/libexec/enclave/enclave-guest-bootstrap
test -f /Library/LaunchAgents/com.enclave.sbxd-darwin.plist
test -f /Library/LaunchDaemons/com.enclave.guest-bootstrap.plist
test -f /var/db/enclave/runtime-seal-required
test -d /Users/admin/Library/Logs/Enclave
test "$(sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser)" = admin
test "$(stat -f '%Su:%Sg:%Lp' /etc/kcpassword)" = root:wheel:600
test -s /etc/kcpassword
sudo launchctl print-disabled system |
  grep -Eq '"com\.openssh\.sshd"[[:space:]]*=>[[:space:]]*true'

# Screen capture and input are driven by Tart's host-side, loopback-only VNC
# endpoint. The runtime image must not depend on unsupported writes to the
# SIP-protected TCC database or grant customer code privileged GUI automation.
test ! -e /usr/local/libexec/enclave/enclave-macos-ui

if security find-generic-password -a AppleID 2>/dev/null; then
  echo "unexpected Apple ID credential found" >&2
  exit 1
fi

printf 'image_acceptance=passed\n'
