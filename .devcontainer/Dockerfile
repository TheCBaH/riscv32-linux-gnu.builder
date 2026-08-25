# Build environment for a riscv32-linux-gnu (glibc) crosstool-ng toolchain.
# ARG VARIANT carries the *full* base image tag (e.g. "debian:13",
# "ubuntu:22.04") rather than just a version number, since this repo's
# matrix spans two distros, not one release train of a single distro.
ARG VARIANT=debian:13
FROM ${VARIANT}

# Pinned crosstool-ng release. crosstool-ng is not packaged on Debian/Ubuntu
# (confirmed: `apt-cache search crosstool` returns nothing on a stock Debian
# 13 host), so it's built from its own source tarball here, once, in the
# build-environment image - never the riscv32 target toolchain itself, which
# only ever gets built by `ct-ng build` inside a CI job.
ARG CTNG_VERSION=crosstool-ng-1.27.0

RUN set -eux; \
    apt-get update; \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      automake \
      bison \
      build-essential \
      ca-certificates \
      ccache \
      curl \
      file \
      flex \
      gawk \
      git \
      gperf \
      help2man \
      libncurses-dev \
      libtool-bin \
      patch \
      python3 \
      qemu-user \
      qemu-user-binfmt \
      rsync \
      texinfo \
      unzip \
      wget \
      xz-utils \
    ; \
    git clone --depth 1 --branch "$CTNG_VERSION" \
      https://github.com/crosstool-ng/crosstool-ng /opt/crosstool-ng-src; \
    cd /opt/crosstool-ng-src; \
    ./bootstrap; \
    ./configure --prefix=/usr/local; \
    make -j"$(nproc)"; \
    make install; \
    cd /; \
    rm -rf /opt/crosstool-ng-src; \
    apt-get autoremove -y; apt-get clean -y; apt-get clean; rm -rf /var/lib/apt/lists/*; \
    echo DONE
