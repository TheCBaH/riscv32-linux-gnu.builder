#!/usr/bin/env bash
# Renders config/rv32gc-ilp32d.config.tmpl, resolves the three detected host
# versions to the closest versions crosstool-ng actually has cataloged, runs
# `ct-ng build`, then restages the result into the packaged layout consumers
# expect. Runs inside the leg's own container (via the vendored devcontainer
# action's `exec` output), with $GCC_VERSION/$BINUTILS_VERSION/$GLIBC_VERSION
# (from scripts/detect-versions.sh) already exported by build.yml.
#
# Split into subcommands - render / defconfig / compile / package - each run
# as its own build.yml step, so a failure in one phase shows up as that
# specific step going red instead of one opaque "build" step.
set -euo pipefail

Fatal() {
  echo "build.sh: $*" >&2
  exit 1
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

# $REPO_ROOT is the same directory bind-mounted as the workspace folder on
# the runner side, so paths under it are reachable from runner-side steps
# (actions/cache, actions/upload-artifact) - unlike a container-local path
# like "~/src". Deterministic, workspace-relative (not mktemp), since each
# subcommand below runs as its own build.yml step and needs to find the
# previous subcommand's output again.
TARBALLS_DIR="$REPO_ROOT/.ctng-cache"
CCACHE_DIR="$REPO_ROOT/.ccache"
CTNG_WORK="$REPO_ROOT/.ctng-work"
PREFIX_DIR="$CTNG_WORK/install"
DIST_DIR="$REPO_ROOT/dist"

# crosstool-ng doesn't let CT_GCC_VERSION/CT_BINUTILS_VERSION/CT_GLIBC_VERSION
# be set to an arbitrary string - each is a Kconfig `string` that is
# computed-only, so writing it directly into a defconfig is silently
# ignored. The buildable versions are a curated, checksummed catalog; pick
# the cataloged version closest to the host's own (resolve-ctng-version.py
# has the nearest-match rule), and use the *resolved* version - not the raw
# host-detected one - everywhere downstream (defconfig, tarball name,
# versions.env) so what's published accurately describes what was built.
resolve_version() {
  local pkg="$1" host_version="$2"
  local ctng_bin ctng_versions_dir
  ctng_bin=$(command -v ct-ng) || Fatal "ct-ng not found on PATH"
  ctng_versions_dir="$(cd -- "$(dirname -- "$ctng_bin")/.." && pwd)/share/crosstool-ng/config/versions"
  python3 "$SCRIPT_DIR/resolve-ctng-version.py" "$ctng_versions_dir/${pkg,,}.in" "$pkg" "$host_version"
}

# Resolves all four package versions and prints "gcc:      X -> Y (Z)"-style
# lines to stdout plus setting $GCC_CHOICE/$RESOLVED_GCC_VERSION etc in the
# caller's shell - used by both `render` (to pick the defconfig's choice
# symbols) and `package` (to name the tarball / write versions.env).
resolve_all_versions() {
  : "${GCC_VERSION:?}"
  : "${BINUTILS_VERSION:?}"
  : "${GLIBC_VERSION:?}"

  # `read` returns non-zero at EOF even when both fields were read
  # successfully (no trailing newline once tr joins the two lines with a
  # space) - `|| true` is safe since the variables are correct regardless;
  # a real resolve_version failure is caught below by the choice guard.
  read -r GCC_CHOICE RESOLVED_GCC_VERSION < <(resolve_version GCC "$GCC_VERSION" | tr '\n' ' ') || true
  read -r BINUTILS_CHOICE RESOLVED_BINUTILS_VERSION < <(resolve_version BINUTILS "$BINUTILS_VERSION" | tr '\n' ' ') || true
  read -r GLIBC_CHOICE RESOLVED_GLIBC_VERSION < <(resolve_version GLIBC "$GLIBC_VERSION" | tr '\n' ' ') || true
  # Fixed target (6.6 LTS), not host-detected like the three above - still
  # goes through the same choice-symbol resolution, since a free-form
  # CT_LINUX_VERSION string is silently ignored the same way.
  read -r LINUX_CHOICE RESOLVED_LINUX_VERSION < <(resolve_version LINUX "6.6.74" | tr '\n' ' ') || true

  : "${GCC_CHOICE:?resolve-ctng-version.py failed to resolve a GCC version}"
  : "${BINUTILS_CHOICE:?resolve-ctng-version.py failed to resolve a binutils version}"
  : "${GLIBC_CHOICE:?resolve-ctng-version.py failed to resolve a glibc version}"
  : "${LINUX_CHOICE:?resolve-ctng-version.py failed to resolve a linux version}"

  echo "== version resolution (host -> crosstool-ng catalog) =="
  echo "gcc:      $GCC_VERSION -> $RESOLVED_GCC_VERSION ($GCC_CHOICE)"
  echo "binutils: $BINUTILS_VERSION -> $RESOLVED_BINUTILS_VERSION ($BINUTILS_CHOICE)"
  echo "glibc:    $GLIBC_VERSION -> $RESOLVED_GLIBC_VERSION ($GLIBC_CHOICE)"
  echo "linux:    6.6.74 -> $RESOLVED_LINUX_VERSION ($LINUX_CHOICE)"
}

cmd_render() {
  resolve_all_versions

  rm -rf "$CTNG_WORK"
  mkdir -p "$CTNG_WORK"
  mkdir -p "$TARBALLS_DIR" "$DIST_DIR"

  sed \
    -e "s|@TARBALLS_DIR@|$TARBALLS_DIR|" \
    -e "s|@PREFIX_DIR@|$PREFIX_DIR|" \
    "$REPO_ROOT/config/rv32gc-ilp32d.config.tmpl" > "$CTNG_WORK/defconfig"

  # Version selection can't be sed-ed into the template (see above) -
  # append the resolved choice symbols as their own defconfig lines.
  {
    echo "$GCC_CHOICE=y"
    echo "$BINUTILS_CHOICE=y"
    echo "$GLIBC_CHOICE=y"
    echo "$LINUX_CHOICE=y"
  } >> "$CTNG_WORK/defconfig"

  echo "== rendered config =="
  cat "$CTNG_WORK/defconfig"
}

cmd_defconfig() {
  [ -f "$CTNG_WORK/defconfig" ] || Fatal "no rendered defconfig at $CTNG_WORK/defconfig - run 'render' first"
  cd "$CTNG_WORK"
  ct-ng defconfig
}

cmd_compile() {
  [ -f "$CTNG_WORK/.config" ] || Fatal "no expanded .config at $CTNG_WORK/.config - run 'defconfig' first"
  cd "$CTNG_WORK"
  # crosstool-ng has no native ccache integration, but most of its build
  # time is ordinary host-side compilation of binutils/gcc/glibc/gdb's own
  # sources - exactly what ccache is for. Debian/Ubuntu's ccache package
  # installs gcc/cc/g++ symlinks under /usr/lib/ccache/; putting that ahead
  # of the real compiler on PATH transparently intercepts every
  # host-compiler invocation ct-ng's build scripts make. Persisted across
  # CI runs via actions/cache on this workspace-relative .ccache dir.
  mkdir -p "$CCACHE_DIR"
  export CCACHE_DIR
  export PATH="/usr/lib/ccache:$PATH"
  ct-ng build
  command -v ccache >/dev/null 2>&1 && ccache -s || true
}

cmd_package() {
  resolve_all_versions

  # ct-ng installs directly into $PREFIX_DIR as the toolchain root (bin/,
  # riscv32-linux-gnu/, lib/gcc/, ...); the sysroot lands one level under
  # that, at <prefix>/<target>/sysroot.
  TOOLCHAIN_ROOT="$PREFIX_DIR"
  SYSROOT_SRC="$TOOLCHAIN_ROOT/riscv32-linux-gnu/sysroot"
  [ -d "$SYSROOT_SRC" ] || Fatal "expected sysroot not found at $SYSROOT_SRC - run 'compile' first"

  # Restage into the layout consumers expect: the sysroot lands directly at
  # /usr/riscv32-linux-gnu (matching err-trace's asm/tools/lib/target.ml
  # qemu_sysroot and how Debian's own cross-libc packages lay out the other
  # five targets), and the full toolchain install lands under
  # /usr/local/<triplet>-toolchain so its bin/ can go on PATH without
  # colliding with anything. Copying $TOOLCHAIN_ROOT wholesale (rather than
  # just bin/ + lib/gcc/) relies on crosstool-ng toolchains being
  # relocatable as a unit when the sysroot is nested under the install
  # prefix - documented ct-ng behavior, exercised by
  # scripts/smoke-test.sh's packaged-artifact pass, which recompiles from
  # the re-extracted, moved location rather than just re-running an
  # already-linked binary.
  DIST_ROOT="$DIST_DIR/root"
  rm -rf "$DIST_ROOT"
  mkdir -p "$DIST_ROOT/usr" "$DIST_ROOT/usr/local"
  cp -a "$SYSROOT_SRC" "$DIST_ROOT/usr/riscv32-linux-gnu"
  cp -a "$TOOLCHAIN_ROOT" "$DIST_ROOT/usr/local/riscv32-linux-gnu-toolchain"

  # `ct-ng build` already collects each component's license file(s) into
  # $PREFIX_DIR/share/licenses while finalizing the install, so the
  # wholesale copy above already carries them into the packaged tarball -
  # see THIRD-PARTY-NOTICES.md.

  TARBALL="$DIST_DIR/riscv32-linux-gnu-${RESOLVED_GCC_VERSION}-${DISTRO:-unknown}-${DISTRO_VER:-unknown}-${ARCH:-unknown}.tar.xz"
  tar -C "$DIST_ROOT" -cJf "$TARBALL" .
  ( cd "$DIST_DIR" && sha256sum "$(basename "$TARBALL")" > SHASUMS256.txt )

  # Records what was actually built (resolved catalog versions) alongside
  # what the host itself reported, so a mismatch stays visible.
  cat > "$DIST_DIR/versions.env" <<EOF
GCC_VERSION=$RESOLVED_GCC_VERSION
BINUTILS_VERSION=$RESOLVED_BINUTILS_VERSION
GLIBC_VERSION=$RESOLVED_GLIBC_VERSION
HOST_GCC_VERSION=$GCC_VERSION
HOST_BINUTILS_VERSION=$BINUTILS_VERSION
HOST_GLIBC_VERSION=$GLIBC_VERSION
EOF

  echo "== packaged: $TARBALL =="
  ls -la "$DIST_DIR"

  # $PREFIX_DIR (the install output) stays around for build.yml's
  # build-tree smoke test step, which runs right after this - only ct-ng's
  # large intermediate build tree is disposable here.
  rm -rf "$CTNG_WORK/.build"
}

case "${1:-}" in
  render) cmd_render ;;
  defconfig) cmd_defconfig ;;
  compile) cmd_compile ;;
  package) cmd_package ;;
  *) Fatal "usage: $0 {render|defconfig|compile|package}" ;;
esac
