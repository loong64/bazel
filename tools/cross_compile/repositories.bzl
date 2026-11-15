# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Configure a local cross compiler with rules_cc's Unix autoconfiguration."""

load("@rules_cc//cc/private/toolchain:unix_cc_configure.bzl", "configure_unix_toolchain")

def _shell_quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def _configure_zig(ctx, cpu, zig):
    targets = {
        "s390x": "s390x-linux-gnu.2.28",
        "ppc64le": "powerpc64le-linux-gnu.2.28",
        "riscv64": "riscv64-linux-gnu.2.31",
        "loongarch64": "loongarch64-linux-gnu.2.38",
    }
    if cpu not in targets or not zig.startswith("/") or not ctx.path(zig).exists:
        fail("Set BAZEL_CROSS_ZIG to an existing absolute Zig path and select a supported CPU")
    # Zig's cc driver does not enable libc++ headers, while c++ treats .c
    # inputs as C++. Select the driver from the compilation language.
    ctx.file("extra_tools/bin/gcc", """#!/bin/sh
export ZIG_GLOBAL_CACHE_DIR="${TMPDIR:-/tmp}/bazel-zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="${TMPDIR:-/tmp}/bazel-zig-local-cache"
driver=c++
previous=
for arg in "$@"; do
  if [ "$previous" = -x ] && [ "$arg" = c ]; then driver=cc; fi
  case "$arg" in -xc|*.c) driver=cc ;; esac
  previous=$arg
done
exec %s "$driver" -target %s "$@"
""" % (_shell_quote(zig), _shell_quote(targets[cpu])), executable = True)
    ctx.file("extra_tools/bin/ar", "#!/bin/sh\nexec %s ar \"$@\"\n" % _shell_quote(zig), executable = True)
    tools = {"gcc": str(ctx.path("extra_tools/bin/gcc")), "cpp": str(ctx.path("extra_tools/bin/gcc")), "ar": str(ctx.path("extra_tools/bin/ar"))}
    for name, command in {"ld": "ld.lld", "nm": "llvm-nm", "objcopy": "llvm-objcopy", "objdump": "llvm-objdump", "strip": "llvm-strip", "c++filt": "llvm-cxxfilt", "gcov": "llvm-cov", "dwp": "llvm-dwp"}.items():
        path = ctx.which(command)
        if not path:
            fail("Zig cross compilation requires " + command + " on PATH")
        tools[name] = str(path)
    configure_unix_toolchain(ctx, cpu, tools)

def _cross_repository_impl(ctx):
    cpu = ctx.os.environ.get("BAZEL_CROSS_CPU", "")
    java_home = ctx.os.environ.get("BAZEL_CROSS_JAVA_HOME", "")
    zig = ctx.os.environ.get("BAZEL_CROSS_ZIG", "")
    if not cpu or not zig.startswith("/") or not java_home.startswith("/"):
        fail("Set BAZEL_CROSS_CPU, absolute BAZEL_CROSS_ZIG and absolute BAZEL_CROSS_JAVA_HOME with --repo_env")
    java_version = 0
    for line in ctx.read(java_home + "/release").splitlines():
        if line.startswith("JAVA_VERSION="):
            java_version = int(line.split('"')[1].split(".")[0].split("-")[0].split("+")[0])

    _configure_zig(ctx, cpu, zig)
    # Change only the target toolchain; BAZEL_LINKLIBS also affects host tools.
    ctx.file("BUILD", ctx.read("BUILD").replace('"-lstdc++"', '"-lc++"'))
    ctx.file("BUILD", "load(\"@rules_java//java/toolchains:java_runtime.bzl\", \"java_runtime\")\n" + ctx.read("BUILD") + """
platform(name = "target", constraint_values = ["@platforms//os:linux", "@platforms//cpu:%s"])
toolchain(
    name = "cc_toolchain",
    exec_compatible_with = ["@platforms//os:linux"],
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:%s"],
    toolchain = ":cc-compiler-%s",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)
java_runtime(name = "java_runtime", java_home = %r, version = %d)
toolchain(
    name = "java_toolchain",
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:%s"],
    toolchain = ":java_runtime",
    toolchain_type = "@bazel_tools//tools/jdk:runtime_toolchain_type",
)
""" % (cpu, cpu, cpu, java_home, java_version, cpu))

_cross_repository = repository_rule(
    implementation = _cross_repository_impl,
    environ = [
        "BAZEL_CROSS_CPU",
        "BAZEL_CROSS_JAVA_HOME",
        "BAZEL_CROSS_ZIG",
        # Variables read by rules_cc's configure_unix_toolchain.
        "ABI_LIBC_VERSION",
        "ABI_VERSION",
        "AR",
        "BAZEL_COMPILER",
        "BAZEL_HOST_SYSTEM",
        "BAZEL_CONLYOPTS",
        "BAZEL_CXXOPTS",
        "BAZEL_LINKOPTS",
        "BAZEL_LINKLIBS",
        "BAZEL_LLVM_COV",
        "BAZEL_LLVM_PROFDATA",
        "BAZEL_TARGET_CPU",
        "BAZEL_TARGET_LIBC",
        "BAZEL_TARGET_SYSTEM",
        "BAZEL_USE_LLVM_NATIVE_COVERAGE",
        "BAZEL_IGNORE_SYSTEM_HEADERS_VERSIONS",
        "CC_CONFIGURE_DEBUG",
        "CC_TOOLCHAIN_NAME",
        "CPLUS_INCLUDE_PATH",
        "DEVELOPER_DIR",
        "PATH",
        "USER",
    ],
    local = True,
    configure = True,
)

def _cross_extension_impl(_module_ctx):
    _cross_repository(name = "bazel_cross")

cross_extension = module_extension(implementation = _cross_extension_impl)
