# Third-party notices

`LICENSE` (MIT) covers this repository's own source — the scripts,
Dockerfile, and GitHub Actions workflows that build the toolchain. It does
**not** cover the contents of the published `riscv32-linux-gnu-*.tar.xz`
release assets: those are compiled binaries of upstream GNU/Linux projects,
each under its own license, unrelated to this repo's own MIT license.

## What's bundled

| Component | License | Notes |
|---|---|---|
| GCC (gcc, libgcc, libstdc++) | GPL-3.0-or-later | Runtime pieces (`libgcc`, `libstdc++`) are additionally under the [GCC Runtime Library Exception 3.1](https://www.gnu.org/licenses/gcc-exception-3.1.en.html) — this is what lets a program *compiled with* this toolchain avoid becoming GPL-encumbered by linking against them. |
| Binutils (as, ld, ...) | GPL-3.0-or-later | Some helper libraries are LGPL-2.1-or-later or LGPL-3.0-or-later; both texts are included. |
| glibc (the sysroot's C library) | LGPL-2.1-or-later | Dynamically linking a program against the packaged libc is unrestricted. Statically linking it carries LGPL relinking obligations (§6) — dynamic linking is the simpler choice for a redistributed binary. |
| Linux kernel UAPI headers (sysroot's `include/linux`, `include/asm`, ...) | GPL-2.0 only, `WITH Linux-syscall-note` | The syscall-note exception explicitly permits using these headers to make system calls from a userspace program without bringing that program under the GPL. |

Each published tarball includes the upstream license text for every
component above, plus every build-time dependency crosstool-ng links in
(gmp, mpfr, mpc, isl, zlib, zstd, expat, gettext, libiconv, ncurses, gdb),
under `usr/local/riscv32-linux-gnu-toolchain/share/licenses/`. This is
collected by `ct-ng build` itself while finalizing the toolchain install —
no extra step in this repo's own scripts.

## Source availability

GPL/LGPL redistribution of binaries requires either including the
corresponding source or pointing at equivalent public access to it. This
project builds exclusively from unmodified upstream release tarballs at
fixed, recorded versions — no local patches. Each release's `versions.env`
records the exact GCC/binutils/glibc versions crosstool-ng built
(`GCC_VERSION`/`BINUTILS_VERSION`/`GLIBC_VERSION`); the matching Linux
version is recorded in this repo's
`config/rv32gc-ilp32d.config.tmpl`. The corresponding source for any of
these is the standard, permanent upstream release at that version:

- GCC: `https://ftp.gnu.org/gnu/gcc/gcc-<version>/`
- Binutils: `https://ftp.gnu.org/gnu/binutils/`
- glibc: `https://ftp.gnu.org/gnu/glibc/`
- Linux: `https://www.kernel.org/`

crosstool-ng itself (the build tool, GPL-2.0-only) is not part of the
published artifact — it only orchestrates the build and is never linked
into or shipped inside the output toolchain/sysroot.
