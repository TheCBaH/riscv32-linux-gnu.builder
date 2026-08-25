#!/usr/bin/env bash
# Detects the GCC/binutils/glibc versions this leg's own base image would
# use for a native riscv64-linux-gnu cross toolchain (Debian/Ubuntu build
# gcc-riscv64-linux-gnu/binutils-riscv64-linux-gnu from the exact same
# source package as native gcc/binutils for that release), so the riscv32
# toolchain this repo builds is an honest match for "what riscv64-linux-gnu
# would have looked like on this release, if it existed for riscv32" rather
# than an arbitrarily pinned version. glibc tracks the host's own libc6.
#
# Must run *inside* the leg's own container (via the vendored devcontainer
# action's `exec` output) - the answer depends on that specific base image,
# not on the runner.
#
# Usage:
#   scripts/detect-versions.sh            emit GCC_VERSION=/BINUTILS_VERSION=/GLIBC_VERSION= to stdout
#   scripts/detect-versions.sh --selftest  run normalize_version() fixture assertions, no apt access needed
set -euo pipefail

# Debian/Ubuntu package versions look like "[epoch:]upstream-revision", e.g.
# "4:12.2.0-3ubuntu1~22.04.1" or "14.2.0-1". crosstool-ng wants the bare
# upstream version ct-ng can actually fetch a tarball for ("12.2.0"). Strip
# the epoch first, then the revision - stripping only the revision leaves
# an epoch prefix like "4:12.2.0" in place, which is not a real gcc release.
normalize_version() {
  local v="$1"
  v="${v#*:}"    # drop optional "N:" epoch prefix (no-op if absent)
  v="${v%%-*}"   # drop "-<revision>" suffix
  printf '%s\n' "$v"
}

selftest() {
  local fail=0
  assert_eq() {
    local got="$1" want="$2" input="$3"
    if [ "$got" != "$want" ]; then
      echo "FAIL: normalize_version('$input') = '$got', want '$want'" >&2
      fail=1
    fi
  }
  assert_eq "$(normalize_version '4:12.2.0-3ubuntu1~22.04.1')" "12.2.0" "4:12.2.0-3ubuntu1~22.04.1"
  assert_eq "$(normalize_version '2:11.4.0-1ubuntu1')" "11.4.0" "2:11.4.0-1ubuntu1"
  assert_eq "$(normalize_version '14.2.0-1')" "14.2.0" "14.2.0-1"
  assert_eq "$(normalize_version '2.44-3')" "2.44" "2.44-3"
  assert_eq "$(normalize_version '2.41')" "2.41" "2.41"
  if [ "$fail" -ne 0 ]; then
    echo "detect-versions.sh --selftest: FAILED" >&2
    exit 1
  fi
  echo "detect-versions.sh --selftest: OK"
}

if [ "${1:-}" = "--selftest" ]; then
  selftest
  exit 0
fi

# The devcontainer's remoteUser (vscode, from the common-utils feature) is
# non-root - refreshing the package list needs sudo; querying the resulting
# cache with apt-cache policy below does not.
sudo apt-get update -qq

pkg_version() {
  apt-cache policy "$1" 2>/dev/null | sed -n 's/^ *Candidate: *//p'
}

GCC_CANDIDATE=$(pkg_version gcc-riscv64-linux-gnu)
if [ -z "$GCC_CANDIDATE" ] || [ "$GCC_CANDIDATE" = "(none)" ]; then
  # Falls back to native gcc's version if this leg's base image doesn't
  # package a riscv64 cross toolchain.
  GCC_CANDIDATE=$(pkg_version gcc)
fi
BINUTILS_CANDIDATE=$(pkg_version binutils-riscv64-linux-gnu)
if [ -z "$BINUTILS_CANDIDATE" ] || [ "$BINUTILS_CANDIDATE" = "(none)" ]; then
  BINUTILS_CANDIDATE=$(pkg_version binutils)
fi
GLIBC_CANDIDATE=$(pkg_version libc6)

[ -n "$GCC_CANDIDATE" ] || { echo "detect-versions.sh: could not determine a GCC version" >&2; exit 1; }
[ -n "$BINUTILS_CANDIDATE" ] || { echo "detect-versions.sh: could not determine a binutils version" >&2; exit 1; }
[ -n "$GLIBC_CANDIDATE" ] || { echo "detect-versions.sh: could not determine a glibc version" >&2; exit 1; }

printf 'GCC_VERSION=%s\n' "$(normalize_version "$GCC_CANDIDATE")"
printf 'BINUTILS_VERSION=%s\n' "$(normalize_version "$BINUTILS_CANDIDATE")"
printf 'GLIBC_VERSION=%s\n' "$(normalize_version "$GLIBC_CANDIDATE")"
