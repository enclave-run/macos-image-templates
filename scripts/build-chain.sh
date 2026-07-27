#!/bin/bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: $0 <macos-version> <xcode-version> <sbxd-darwin> <guest-bootstrap> <macos-ui> <created-vms-file>" >&2
  exit 64
fi

macos_version=$1
xcode_version=$2
sbxd_darwin=$3
guest_bootstrap=$4
macos_ui=$5
created_vms_file=$6

case "$macos_version" in
  tahoe|sequoia|sonoma) ;;
  *)
    echo "unsupported macOS version: $macos_version" >&2
    exit 64
    ;;
esac

if [[ ! "$xcode_version" =~ ^[0-9]+([.][0-9]+){1,3}([._-][A-Za-z0-9]+)?$ ]]; then
  echo "invalid Xcode version: $xcode_version" >&2
  exit 64
fi

for artifact in "$sbxd_darwin" "$guest_bootstrap" "$macos_ui"; do
  if [[ ! -f "$artifact" || "$artifact" != /* ]]; then
    echo "guest artifact must be an absolute file path: $artifact" >&2
    exit 66
  fi
done

if [[ "$created_vms_file" != /* ]]; then
  echo "created VMs file must be absolute: $created_vms_file" >&2
  exit 64
fi
umask 077
mkdir -p "$(dirname "$created_vms_file")"
if ! (set -o noclobber; : >"$created_vms_file") 2>/dev/null; then
  echo "refusing existing created VMs file: $created_vms_file" >&2
  exit 73
fi

xcode_archive=${XCODE_APP_ARCHIVE:-"$HOME/XcodesCache/Xcode_${xcode_version}.xip"}
xcode_archive_sha256=${XCODE_APP_ARCHIVE_SHA256:-}
if [[ ! -f "$xcode_archive" || "$xcode_archive" != /* ]]; then
  echo "missing absolute pinned Xcode archive: $xcode_archive" >&2
  exit 66
fi
if [[ "$xcode_archive" == *.zip && ! "$xcode_archive_sha256" =~ ^[a-f0-9]{64}$ ]]; then
  echo "XCODE_APP_ARCHIVE_SHA256 is required for a trusted zip bootstrap" >&2
  exit 64
fi
if [[ "$xcode_archive" != *.zip && -n "$xcode_archive_sha256" ]]; then
  echo "XCODE_APP_ARCHIVE_SHA256 is only valid with a zip bootstrap" >&2
  exit 64
fi

builder_password=$(openssl rand -hex 16)
export PKR_VAR_builder_password=$builder_password

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

printf '%s\n' "$vanilla_name" >>"$created_vms_file"
packer init "templates/vanilla-$macos_version.pkr.hcl"
packer build "templates/vanilla-$macos_version.pkr.hcl"

printf '%s\n' "$base_name" >>"$created_vms_file"
tart clone "$vanilla_name" "$base_name"
packer init templates/base.pkr.hcl
packer build \
  -var "vm_name=$base_name" \
  -var "sbxd_darwin_path=$sbxd_darwin" \
  -var "guest_bootstrap_path=$guest_bootstrap" \
  -var "macos_ui_path=$macos_ui" \
  templates/base.pkr.hcl

printf '%s\n' "$xcode_name" >>"$created_vms_file"
packer init templates/xcode.pkr.hcl
xcode_args=(
  -var "base_image=$base_name"
  -var "macos_version=$macos_version"
  -var "xcode_version=[\"$xcode_version\"]"
)
if [[ "$xcode_archive" == *.zip ]]; then
  xcode_args+=(
    -var "xcode_app_archive=$xcode_archive"
    -var "xcode_app_archive_sha256=$xcode_archive_sha256"
  )
else
  expected_runtimes="data/expected.$macos_version.runtimes.txt"
  [[ -f "$expected_runtimes" ]] &&
    xcode_args+=(-var "expected_runtimes_file=$expected_runtimes")
fi
packer build "${xcode_args[@]}" templates/xcode.pkr.hcl

printf 'built_vanilla=%s\nbuilt_base=%s\nbuilt_xcode=%s\n' \
  "$vanilla_name" "$base_name" "$xcode_name"
