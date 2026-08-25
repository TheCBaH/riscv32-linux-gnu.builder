#!/usr/bin/env bash
# Smoke-tests a just-built (or just-packaged) riscv32-linux-gnu toolchain by
# compiling and running three fixtures under qemu-user: a dynamically-linked
# hello-world, a statically-linked one, and a pthread+malloc program.
#
# Two invocation forms:
#   scripts/smoke-test.sh --build-tree <ct-ng PREFIX_DIR>
#     Tests the pre-packaging build tree directly.
#   scripts/smoke-test.sh --packaged <tarball path>
#     Re-extracts the packaged tarball into a fresh throwaway root and
#     compiles+links+runs from THAT location - proves the published
#     artifact's gcc resolves its own (relocated) sysroot correctly, not
#     just that an already-linked binary still runs.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TOOLPREFIX="riscv32-linux-gnu-"
QEMU_BIN="qemu-riscv32"

Fatal() {
  echo "FATAL: $*" >&2
  exit 1
}

case "${1:-}" in
  --build-tree)
    PREFIX_DIR="${2:?usage: $0 --build-tree <PREFIX_DIR>}"
    # Resolve to absolute now - build.yml passes this relative
    # (.ctng-work/install), and the `cd "$WORK"` below would otherwise
    # silently break it once $CC is invoked from that throwaway dir.
    PREFIX_DIR=$(cd -- "$PREFIX_DIR" && pwd) || Fatal "--build-tree directory not found: $PREFIX_DIR"
    TOOLCHAIN_BIN="$PREFIX_DIR/bin"
    QEMU_SYSROOT="$PREFIX_DIR/riscv32-linux-gnu/sysroot"
    LABEL="build-tree"
    ;;
  --packaged)
    TARBALL="${2:?usage: $0 --packaged <tarball>}"
    [ -f "$TARBALL" ] || Fatal "tarball not found: $TARBALL"
    EXTRACT_ROOT=$(mktemp -d)
    tar -C "$EXTRACT_ROOT" -xf "$TARBALL"
    TOOLCHAIN_BIN="$EXTRACT_ROOT/usr/local/riscv32-linux-gnu-toolchain/bin"
    # The doc-facing /usr/riscv32-linux-gnu copy, not the toolchain's own
    # <toolchain>/riscv32-linux-gnu/sysroot - proves that path is
    # independently usable, matching what a consumer extracting only it
    # (not the full toolchain) needs.
    QEMU_SYSROOT="$EXTRACT_ROOT/usr/riscv32-linux-gnu"
    LABEL="packaged"
    ;;
  *)
    Fatal "usage: $0 --build-tree <PREFIX_DIR> | --packaged <tarball>"
    ;;
esac

CC="$TOOLCHAIN_BIN/${TOOLPREFIX}gcc"
[ -x "$CC" ] || Fatal "[$LABEL] compiler not found or not executable: $CC"
command -v "$QEMU_BIN" >/dev/null 2>&1 || Fatal "[$LABEL] $QEMU_BIN not found on PATH"
[ -d "$QEMU_SYSROOT" ] || Fatal "[$LABEL] qemu sysroot not found: $QEMU_SYSROOT"

WORK=$(mktemp -d)
cd "$WORK"

echo "== [$LABEL] compiling fixtures with $CC (no explicit --sysroot: relies on gcc's own default lookup) =="
"$CC" -o hello.dyn "$FIXTURES_DIR/hello.c"
"$CC" -static -o hello.static "$FIXTURES_DIR/hello.c"
"$CC" -pthread -o pthread_malloc "$FIXTURES_DIR/pthread_malloc.c"

echo "== [$LABEL] checking ELF machine type =="
actual_machine=$(readelf -h hello.dyn | sed -n 's/^ *Machine: *//p')
[ "$actual_machine" = "RISC-V" ] || Fatal "[$LABEL] expected ELF machine 'RISC-V', got '$actual_machine'"

echo "== [$LABEL] running dynamic hello-world under qemu (-L $QEMU_SYSROOT) =="
out=$(timeout 10s "$QEMU_BIN" -L "$QEMU_SYSROOT" ./hello.dyn)
[ "$out" = "hello riscv32" ] || Fatal "[$LABEL] dynamic hello-world: expected 'hello riscv32', got '$out'"

echo "== [$LABEL] running static hello-world under qemu (no -L) =="
out=$(timeout 10s "$QEMU_BIN" ./hello.static)
[ "$out" = "hello riscv32" ] || Fatal "[$LABEL] static hello-world: expected 'hello riscv32', got '$out'"

echo "== [$LABEL] running pthread+malloc program under qemu =="
out=$(timeout 10s "$QEMU_BIN" -L "$QEMU_SYSROOT" ./pthread_malloc)
[ "$out" = "pthread+malloc ok: 42" ] || Fatal "[$LABEL] pthread+malloc: expected 'pthread+malloc ok: 42', got '$out'"

cd /
rm -rf "$WORK"
# glibc's `make install` leaves installed headers read-only, which
# survives packaging/re-extraction - `rm -rf` needs write permission on a
# directory's *parent*, not the entry itself, so chmod first.
if [ -n "${EXTRACT_ROOT:-}" ]; then
  chmod -R u+w "$EXTRACT_ROOT"
  rm -rf "$EXTRACT_ROOT"
fi

echo "== [$LABEL] OK: all smoke tests passed =="
