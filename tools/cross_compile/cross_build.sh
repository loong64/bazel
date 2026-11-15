#!/usr/bin/env bash
# Copyright 2026 The Bazel Authors. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
set -euo pipefail

: "${BAZEL_CROSS_CPU:?Set BAZEL_CROSS_CPU}"
: "${BAZEL_CROSS_ZIG:?Set BAZEL_CROSS_ZIG to the absolute Zig executable}"
: "${BAZEL_CROSS_JAVA_HOME:?Set BAZEL_CROSS_JAVA_HOME to an absolute target JDK path}"
if [[ $BAZEL_CROSS_ZIG != /* || $BAZEL_CROSS_JAVA_HOME != /* ]]; then
  echo 'Zig and target JDK must be absolute paths.' >&2
  exit 2
fi
if (( $# > 1 )); then
  echo "Usage: $0 [OUTPUT_DIRECTORY]" >&2
  exit 2
fi
cd "$(dirname "$0")/../.."
mkdir -p output/cross-runs
run_dir=${1:-$(mktemp -d "$PWD/output/cross-runs/run.XXXXXXXX")}
if [[ $run_dir != /* ]]; then
  echo 'Output directory must be an absolute path.' >&2
  exit 2
fi
mkdir -p "$run_dir"
if [[ -e $run_dir/sysroot || -L $run_dir/sysroot || -e $run_dir/bazel-root || -L $run_dir/bazel-root ]]; then
  echo "Use a fresh output directory: $run_dir" >&2
  exit 2
fi
bazel=${BAZEL_BINARY:-bazelisk}
RELEASE_NAME=${RELEASE_NAME:-unknown}
bash tools/cross_compile/prepare_sysroot.sh "$BAZEL_CROSS_CPU" "$run_dir/sysroot"
"$bazel" --output_base="$run_dir/bazel-root" build --sandbox_tmpfs_path=/tmp //src:bazel
mkdir -p output
cp bazel-bin/src/bazel output/bazel
# Use a fresh output base and disable external caches for the local toolchain.
output/bazel --output_base="$run_dir/bazel-root" build //src:bazel //src:bazel_nojdk //scripts/packages:with-jdk/install.sh -c opt \
  --stamp --embed_label "$RELEASE_NAME" \
  --sandbox_tmpfs_path=/tmp \
  --workspace_status_command=scripts/ci/build_status_command.sh \
  --repo_env="BAZEL_CROSS_CPU=$BAZEL_CROSS_CPU" \
  --repo_env="BAZEL_CROSS_ZIG=$BAZEL_CROSS_ZIG" \
  --repo_env="BAZEL_CROSS_JAVA_HOME=$BAZEL_CROSS_JAVA_HOME" \
  --action_env="JLINK_OBJCOPY=$(command -v llvm-objcopy)" \
  --platforms=@bazel_cross//:target \
  --extra_toolchains=@bazel_cross//:cc_toolchain,@bazel_cross//:java_toolchain \
  --sandbox_add_mount_pair="$(dirname "$BAZEL_CROSS_ZIG")" \
  --sandbox_add_mount_pair="$BAZEL_CROSS_JAVA_HOME" \
  --remote_cache= --remote_executor= --experimental_remote_downloader= \
  --noremote_upload_local_results --disk_cache= --bes_backend=
mkdir -p "$run_dir/artifacts"
cp -p bazel-bin/src/bazel bazel-bin/src/bazel_nojdk "$run_dir/artifacts/"
cp -p bazel-bin/scripts/packages/with-jdk/install.sh "$run_dir/artifacts/install.sh"
cp "$run_dir/sysroot/sysroot-image.txt" "$run_dir/artifacts/"
echo "Artifacts: $run_dir/artifacts"
