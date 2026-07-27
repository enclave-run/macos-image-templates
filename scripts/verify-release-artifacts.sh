#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "usage: $0 /absolute/artifact-directory" >&2
  exit 64
fi

artifact_dir=$1
checksum_file="$artifact_dir/SHA256SUMS"
artifacts=(sbxd-darwin enclave-guest-bootstrap)

[[ -f "$checksum_file" ]] || {
  echo "missing SHA256SUMS" >&2
  exit 66
}

for artifact in "${artifacts[@]}"; do
  path="$artifact_dir/$artifact"
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "missing regular artifact: $artifact" >&2
    exit 66
  }
  expected=$(
    awk -v name="$artifact" '$2 == name { print $1 }' "$checksum_file"
  )
  if [[ ! "$expected" =~ ^[a-f0-9]{64}$ ]] ||
    [[ $(awk -v name="$artifact" '$2 == name { count++ } END { print count + 0 }' "$checksum_file") -ne 1 ]]; then
    echo "missing or ambiguous checksum for $artifact" >&2
    exit 65
  fi
  actual=$(shasum -a 256 "$path" | awk '{ print $1 }')
  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch for $artifact" >&2
    exit 65
  fi
done
