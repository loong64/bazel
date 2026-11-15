#!/usr/bin/env bash
# Copyright 2026 The Bazel Authors. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: $0 {s390x|ppc64le|riscv64|loongarch64} ABSOLUTE_SYSROOT" >&2
  exit 2
fi
cpu=$1
sysroot=$2
case "$cpu" in
  s390x|ppc64le) platform="linux/$cpu"; image=quay.io/almalinuxorg/almalinux:8 ;;
  riscv64) platform=linux/riscv64; image=ubuntu:20.04 ;;
  loongarch64) platform=linux/loong64; image=openanolis/anolisos:23.4 ;;
  *) echo "Unsupported target CPU: $cpu" >&2; exit 2 ;;
esac
if [[ $sysroot != /* || $sysroot == / || -e $sysroot || -L $sysroot ]]; then
  echo 'The sysroot must be an absolute path that does not already exist.' >&2
  exit 2
fi
mkdir -p "$(dirname "$sysroot")"
tmp=$(mktemp -d "$(dirname "$sysroot")/.sysroot.XXXXXXXX")
container_id=
cleanup() {
  if [[ -n $container_id ]]; then docker rm -f "$container_id" >/dev/null 2>&1 || :; fi
  if [[ -n $tmp ]]; then rm -rf "$tmp"; fi
}
trap cleanup EXIT

container_id=$(docker create --platform "$platform" "$image")
mkdir "$tmp/root"
# Device nodes and mounts are not compiler inputs and may require root to extract.
docker export "$container_id" | tar --no-same-owner --exclude='./dev/*' --exclude='dev/*' -xf - -C "$tmp/root"
printf '%s\n' "$image" > "$tmp/root/sysroot-image.txt"
mv -T -n "$tmp/root" "$sysroot"
if [[ -e $tmp/root ]]; then
  echo "Destination appeared while creating sysroot: $sysroot" >&2
  exit 1
fi
echo "Prepared $cpu sysroot at $sysroot from $image"
