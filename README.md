# riscv32-linux-gnu.builder

Cross-builds a `riscv32-linux-gnu` (glibc) toolchain with
[crosstool-ng](https://crosstool-ng.github.io/) and publishes it as GitHub
Release tarballs.

Debian and Ubuntu package `gcc-riscv64-linux-gnu` /
`binutils-riscv64-linux-gnu`, but there is no `riscv32-linux-gnu` glibc cross
toolchain package on either distro (only bare-metal `riscv32-*-elf` ones).
This repo exists so that a consumer (e.g.
[`devcontainer.CompCert`](https://github.com/TheCBaH/err-trace))'s Dockerfile
can `curl` a prebuilt riscv32 toolchain instead of compiling one from source
on every image rebuild.

## What gets built

One toolchain per `(distro, distro_ver, arch)` leg:

| distro | distro_ver | arch |
|---|---|---|
| debian | 12 (bookworm) | amd64, arm64 |
| debian | 13 (trixie) | amd64, arm64 |
| ubuntu | 22.04 (jammy) | amd64, arm64 |
| ubuntu | 24.04 (noble) | amd64, arm64 |

Each leg detects the GCC/binutils/glibc versions its own base image would
use for a native `riscv64-linux-gnu` cross toolchain
(`scripts/detect-versions.sh`), then builds the riscv32 toolchain against
the closest version crosstool-ng actually has cataloged for each of the
three packages (`scripts/resolve-ctng-version.py`) — crosstool-ng only
builds from a curated, checksummed catalog of released tarballs, not an
arbitrary version string, so an exact match isn't always available (see the
comment block in `config/rv32gc-ilp32d.config.tmpl` for why). Every
published asset's `versions.env` records both what was actually built
(`GCC_VERSION`/`BINUTILS_VERSION`/`GLIBC_VERSION`) and what the host itself
reported (`HOST_GCC_VERSION`/`HOST_BINUTILS_VERSION`/`HOST_GLIBC_VERSION`),
so a mismatch is visible rather than silently glossed over.

Pushing a git tag publishes one GitHub Release under that tag, bundling all
8 legs' tarballs together, plus a combined `SHASUMS256.txt` and build
provenance attestation. A plain push (any branch, no tag) only runs the
build matrix to validate the toolchain still compiles — it publishes
nothing.

## Using a published toolchain

```sh
TAG=v1.0.0   # see: gh release list --repo TheCBaH/riscv32-linux-gnu.builder
ASSET=riscv32-linux-gnu-14.2.0-debian-13-amd64.tar.xz   # one of the 8 legs - see the table above

curl -fsSLO "https://github.com/TheCBaH/riscv32-linux-gnu.builder/releases/download/$TAG/$ASSET"
curl -fsSLO "https://github.com/TheCBaH/riscv32-linux-gnu.builder/releases/download/$TAG/SHASUMS256.txt"
sha256sum -c --ignore-missing SHASUMS256.txt

gh attestation verify "$ASSET" --repo TheCBaH/riscv32-linux-gnu.builder

sudo tar -C / -xf "$ASSET"
export PATH="/usr/local/riscv32-linux-gnu-toolchain/bin:$PATH"
riscv32-linux-gnu-gcc --version
```

This lays down two paths:

- `/usr/riscv32-linux-gnu/` — the sysroot, a drop-in replacement for the
  `qemu -L` sysroot path used by err-trace's other cross targets.
- `/usr/local/riscv32-linux-gnu-toolchain/` — the full toolchain install
  (`bin/`, `lib/gcc/`, ...); only its `bin/` needs to be on `PATH`.

## Triggering a build / publishing a release

The build matrix (all 8 legs) runs on every push to any branch, on
`workflow_dispatch`, and weekly on its own (`schedule` in `build.yml`) — but
none of those publish anything. Publishing only happens when a git tag is
pushed:

```sh
git tag v1.0.0
git push origin v1.0.0
gh run watch --repo TheCBaH/riscv32-linux-gnu.builder
```

A manual build without publishing:

```sh
gh workflow run build.yml --repo TheCBaH/riscv32-linux-gnu.builder
gh run watch --repo TheCBaH/riscv32-linux-gnu.builder
```

Publishing is idempotent per tag: an existing release is left alone, so a
rerun after a partial failure is safe.

## License

This repository's own source (scripts, Dockerfile, workflows) is MIT —
see `LICENSE`. The published toolchain tarballs bundle GCC/binutils/glibc/
Linux headers under their own upstream licenses (mostly GPL/LGPL); see
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) for the breakdown and
where each tarball's `share/licenses/` comes from.

## Local development

`scripts/build.sh` runs a real `ct-ng build`, which takes on the order of an
hour and several GB of disk per leg — this is only ever run in CI (GitHub-
hosted runners), never expected to complete locally. Everything short of
that (`scripts/detect-versions.sh --selftest`, `bash -n` on the scripts, the
devcontainer image build itself) is fine to run locally; see
`.devcontainer/` for the crosstool-ng build environment.
