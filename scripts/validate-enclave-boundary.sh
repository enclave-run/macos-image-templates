#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if command -v rg >/dev/null 2>&1; then
  runtime_dependency_matches=$(
    rg -n 'ghcr\.io/cirruslabs' \
      .github templates scripts data enclave \
      --glob '!validate-enclave-boundary.sh' || true
  )
else
  runtime_dependency_matches=$(
    grep -R -n -E 'ghcr\.io/cirruslabs' \
      --exclude=validate-enclave-boundary.sh \
      .github templates scripts data enclave || true
  )
fi

if [[ -n "$runtime_dependency_matches" ]]; then
  printf '%s\n' "$runtime_dependency_matches"
  echo "Cirrus runtime image dependency found" >&2
  exit 1
fi

for forbidden in \
  templates/disable-sip.pkr.hcl \
  templates/disable-sip-with-username.pkr.hcl \
  scripts/install-actions-runner.sh \
  data/tart-guest-agent.plist \
  data/tart-guest-daemon.plist; do
  if [[ -e "$forbidden" ]]; then
    echo "forbidden inherited payload exists: $forbidden" >&2
    exit 1
  fi
done

if command -v rg >/dev/null 2>&1; then
  inherited_payload_matches=$(
    rg -n 'tart-guest-agent|actions-runner|gitlab-runner|buildkite-agent' \
      templates scripts data --glob '!validate-enclave-boundary.sh' || true
  )
else
  inherited_payload_matches=$(
    grep -R -n -E 'tart-guest-agent|actions-runner|gitlab-runner|buildkite-agent' \
      --exclude=validate-enclave-boundary.sh \
      templates scripts data || true
  )
fi

if [[ -n "$inherited_payload_matches" ]]; then
  printf '%s\n' "$inherited_payload_matches"
  echo "inherited runner or FSL guest-agent payload found" >&2
  exit 1
fi

echo "Enclave image boundary is clean"
