#!/bin/bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <macos-version> <xcode-version> <sbxd-darwin> <guest-bootstrap> <macos-ui>" >&2
  exit 64
fi

macos_version=$1
xcode_version=$2
sbxd_darwin=$3
guest_bootstrap=$4
macos_ui=$5

case "$macos_version" in
  tahoe|sequoia|sonoma) ;;
  *)
    echo "unsupported macOS version: $macos_version" >&2
    exit 64
    ;;
esac

for artifact in "$sbxd_darwin" "$guest_bootstrap" "$macos_ui"; do
  if [[ ! -f "$artifact" || "$artifact" != /* ]]; then
    echo "guest artifact must be an absolute file path: $artifact" >&2
    exit 66
  fi
done

xcode_archive="$HOME/XcodesCache/Xcode_${xcode_version}.xip"
if [[ ! -f "$xcode_archive" ]]; then
  echo "missing pinned Xcode archive: $xcode_archive" >&2
  exit 66
fi

scripts/validate-enclave-boundary.sh

vanilla_name="$macos_version-vanilla"
base_name="$macos_version-base"
xcode_name="$macos_version-xcode:$xcode_version"

for vm_name in "$vanilla_name" "$base_name" "$xcode_name"; do
  if tart list --source local --quiet | grep -Fxq "$vm_name"; then
    echo "refusing to overwrite existing VM: $vm_name" >&2
    exit 73
  fi
done

packer init "templates/vanilla-$macos_version.pkr.hcl"
packer build "templates/vanilla-$macos_version.pkr.hcl"

tart clone "$vanilla_name" "$base_name"
packer init templates/base.pkr.hcl
packer build \
  -var "vm_name=$base_name" \
  -var "sbxd_darwin_path=$sbxd_darwin" \
  -var "guest_bootstrap_path=$guest_bootstrap" \
  -var "macos_ui_path=$macos_ui" \
  templates/base.pkr.hcl

packer init templates/xcode.pkr.hcl
packer build \
  -var "base_image=$base_name" \
  -var "macos_version=$macos_version" \
  -var "xcode_version=[\"$xcode_version\"]" \
  -var "expected_runtimes_file=data/expected.$macos_version.runtimes.txt" \
  templates/xcode.pkr.hcl

printf 'built_vanilla=%s\nbuilt_base=%s\nbuilt_xcode=%s\n' \
  "$vanilla_name" "$base_name" "$xcode_name"
