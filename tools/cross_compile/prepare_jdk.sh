#!/usr/bin/env bash
# Copyright 2026 The Bazel Authors. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
set -euo pipefail
if [[ $# != 2 || $2 != /* ]]; then
  echo "Usage: $0 {s390x|ppc64le|riscv64|loongarch64} ABSOLUTE_OUTPUT_DIRECTORY" >&2
  exit 2
fi
cpu=$1
out=$2
jdk_version=25.0.2
jdk_build=10
jdk_major=${jdk_version%%.*}
loongson_version=25.3.20
base="https://github.com/adoptium/temurin${jdk_major}-binaries/releases/download/jdk-${jdk_version}%2B${jdk_build}"
case "$cpu" in
  s390x|ppc64le|riscv64) name="OpenJDK${jdk_major}U-jdk_${cpu}_linux_hotspot_${jdk_version}_${jdk_build}.tar.gz" ;;
  loongarch64) base="https://ftp.loongnix.cn/Java/openjdk${jdk_major}"; name="loongson${loongson_version}-fx-jdk${jdk_version}_${jdk_build}-linux-loongarch64-glibc2.34.tar.gz" ;;
  *) echo "Unsupported CPU: $cpu" >&2; exit 2 ;;
esac
if [[ -e $out || -L $out ]]; then
  echo "Destination already exists: $out" >&2; exit 2
fi
mkdir -p "$(dirname "$out")"
tmp=$(mktemp -d "$(dirname "$out")/.cross-jdk.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
curl -fL --retry 3 -o "$tmp/jdk.tar.gz" "$base/$name"
mkdir "$tmp/ready"
tar -xzf "$tmp/jdk.tar.gz" -C "$tmp/ready" --strip-components=1
mv -T -n "$tmp/ready" "$out"
if [[ -e $tmp/ready ]]; then
  echo "Destination appeared while downloading: $out" >&2
  exit 1
fi
echo "Prepared JDK in $out"
