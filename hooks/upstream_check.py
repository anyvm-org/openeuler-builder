#!/usr/bin/env python3
# Print the newest openEuler release with a published VM image, e.g.
# "25.09" or "24.03-LTS-SP4". Empty output means "nothing detected" and is
# not an error; a non-zero exit means detection itself is broken (network
# error, HTTP error, or a page that no longer matches the expected shape)
# and must be reported by the caller, never swallowed. A failure must
# NEVER print a plausible-but-wrong version -- the version is only printed
# after every step below has succeeded.
#
# Source of truth: https://repo.openeuler.org/
# Fetched and confirmed by hand (2026-07-26): the directory is a plain
# Apache-style autoindex, one row per line, e.g.
#   <tr><td colspan="2" class="link">
#     <a href="openEuler-25.09/" title="openEuler-25.09">openEuler-25.09/</a>
#   </td>...
# Real releases sit at the top level as "openEuler-<ver>/", where <ver> is
# either a bare "XX.XX" interim release (20.09, 21.03, ..., 25.09) or an
# LTS chain "XX.XX-LTS" plus its service packs "XX.XX-LTS-SPn" (20.03-LTS,
# 20.03-LTS-SP1 .. SP4, 22.03-LTS(-SP1..SP4), 24.03-LTS(-SP1..SP4) at the
# time of checking). Two kinds of entries must NOT be picked up:
#   - a page-size/kernel variant of an existing release, e.g.
#     "openEuler-22.03-LTS-64kb/" -- not a separate release, no VM image;
#   - a different product line entirely, e.g. "openEuler-Embedded-26.03/"
#     (the Embedded/edge track, disjoint from the desktop/server VM images
#     this builder downloads) and "openEuler-preview/".
# The pattern below anchors "XX.XX" immediately after "openEuler-" and only
# allows an optional "-LTS" then an optional "-SPn" before the trailing
# slash, which excludes both of the above without an explicit denylist.
#
# stdlib only (urllib.request, re, sys, os) -- no external dependencies.

import os
import re
import sys
import urllib.request

URL = "https://repo.openeuler.org/"
TIMEOUT = 60
USER_AGENT = "anyvm-org-upstream-watcher/1.0"

PATTERN = re.compile(r'href="openEuler-(\d{2}\.\d{2}(?:-LTS(?:-SP\d+)?)?)/"')


def resolve_natural_key():
    """Return the engine's own natural_key, or fail loudly.

    watch.yml clones base-builder INTO the builder repo root, so at
    detection time it sits at "base-builder/" (relative to this hook's
    cwd, the builder repo root). A local checkout instead has it as a
    sibling, "../base-builder". Try both, in that order.

    There is deliberately NO local fallback copy. Ordering must be the
    single rule the engine uses -- a per-hook duplicate would have to be
    kept in sync by hand across every builder and would drift silently,
    and a hook that ranks versions differently from watch.py is worse
    than one that refuses to run. Both real contexts (CI and a local
    sibling checkout) always provide base-builder, so an ImportError here
    means the environment is wrong: report it as broken detection rather
    than guessing an order.
    """
    for candidate in ("base-builder", os.path.join("..", "base-builder")):
        if not os.path.isdir(candidate):
            continue
        path = os.path.abspath(candidate)
        if path not in sys.path:
            sys.path.insert(0, path)
        try:
            import gendata
            return gendata.natural_key
        except ImportError:
            continue
    raise ImportError(
        "base-builder/gendata.py not importable from %s; expected it at "
        "./base-builder (CI) or ../base-builder (local checkout)"
        % os.getcwd())


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read().decode("utf-8", "replace")


def main():
    try:
        key = resolve_natural_key()
    except ImportError as e:
        sys.stderr.write("upstream_check: %s\n" % e)
        return 1
    try:
        html = fetch(URL)
    except Exception as e:
        sys.stderr.write("upstream_check: fetch of %s failed: %s\n"
                         % (URL, e))
        return 1
    versions = PATTERN.findall(html)
    if not versions:
        sys.stderr.write("upstream_check: no openEuler-<ver> directory "
                         "found in %s; page shape may have changed\n" % URL)
        return 1
    newest = sorted(set(versions), key=key)[-1]
    print(newest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
