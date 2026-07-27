#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "usage: $0 /absolute/created-vms-file" >&2
  exit 64
fi

created_vms_file=$1
[[ -f "$created_vms_file" ]] || exit 0

cleanup_failed=0
while IFS= read -r vm_name; do
  if [[ ! "$vm_name" =~ ^(tahoe|sequoia|sonoma)-(vanilla|base|xcode:[0-9]+([.][0-9]+){1,3}([._-][A-Za-z0-9]+)?)$ ]]; then
    echo "refusing unsafe VM name in cleanup manifest: $vm_name" >&2
    cleanup_failed=1
    continue
  fi
  if ! tart list --source local --quiet | grep -Fxq "$vm_name"; then
    continue
  fi
  if ! tart delete "$vm_name"; then
    echo "failed to delete owned build VM: $vm_name" >&2
    cleanup_failed=1
  fi
done <"$created_vms_file"

exit "$cleanup_failed"
