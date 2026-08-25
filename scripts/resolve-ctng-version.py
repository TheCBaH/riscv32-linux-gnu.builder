#!/usr/bin/env python3
"""Resolve a host-detected package version to the closest version crosstool-ng
actually has cataloged, and the Kconfig choice symbol that selects it.

crosstool-ng doesn't let you set CT_GCC_VERSION/CT_BINUTILS_VERSION/
CT_GLIBC_VERSION to an arbitrary string: each is a Kconfig `string` with only
`default "X" if PKG_V_SYM` entries and no prompt of its own, so it is
computed-only - writing it directly into a defconfig is silently ignored.
The buildable versions are a curated, checksummed catalog (one choice member
per PKG_V_SYM), generated at bootstrap time into
<ct-ng prefix>/share/crosstool-ng/config/versions/<pkg>.in. You select a
version by setting that choice symbol (e.g. CT_GCC_V_12=y), not the string.

This picks the catalog entry closest to the host's own version so the built
toolchain matches "what this Debian/Ubuntu release itself ships" as closely
as crosstool-ng's own release allows: exact (major, minor) match if
cataloged, else the nearest minor within the same major, else the nearest
major overall.
"""
import re
import sys


def parse_version(v):
    parts = re.split(r"[._]", v)
    nums = []
    for p in parts:
        m = re.match(r"\d+", p)
        if not m:
            break
        nums.append(int(m.group()))
    if len(nums) < 2:
        nums += [0] * (2 - len(nums))
    return tuple(nums[:2])


def load_catalog(versions_in_path, pkg):
    # config PKG_V_<sym>\n    bool "X.Y.Z"   -- one choice member per cataloged version.
    text = open(versions_in_path).read()
    pattern = re.compile(
        r'^config ' + re.escape(pkg) + r'_V_([0-9_]+)\s*\n\s*bool "([^"]+)"',
        re.MULTILINE,
    )
    catalog = {}
    for sym, actual in pattern.findall(text):
        catalog[sym] = (parse_version(actual), actual)
    return catalog


def pick(catalog, host_key):
    host_major, host_minor = host_key
    exact = [s for s, (k, _) in catalog.items() if k == host_key]
    if exact:
        return exact[0]

    same_major = [(s, k, a) for s, (k, a) in catalog.items() if k[0] == host_major]
    if same_major:
        not_newer = [(s, k) for s, k, _a in same_major if k[1] <= host_minor]
        if not_newer:
            return max(not_newer, key=lambda t: t[1])[0]
        return min(same_major, key=lambda t: t[1])[0]

    # No cataloged entry shares the host's major at all: fall back to the
    # closest major overall (ties broken toward the newer one).
    def dist(item):
        _s, (k, _a) = item
        return (abs(k[0] - host_major), -k[0])

    return min(catalog.items(), key=dist)[0]


def main():
    if len(sys.argv) != 4:
        print(
            "usage: resolve-ctng-version.py <versions.in path> <PKG_PREFIX> <host_version>",
            file=sys.stderr,
        )
        return 2
    versions_in_path, pkg, host_version = sys.argv[1:4]
    catalog = load_catalog(versions_in_path, pkg)
    if not catalog:
        print(f"resolve-ctng-version.py: no {pkg}_V_* entries found in {versions_in_path}", file=sys.stderr)
        return 1
    sym = pick(catalog, parse_version(host_version))
    _key, actual = catalog[sym]
    print(f"CT_{pkg}_V_{sym}")
    print(actual)
    return 0


if __name__ == "__main__":
    sys.exit(main())
