#!/bin/bash
# host-side beforeBuild hook -- the earliest hook point in build.py's
# pipeline, before setup() extracts VM_QEMU_TAR.
#
# Generates the pinned QEMU tarball on the fly when the conf asks for one
# (VM_QEMU_TAR): the ~30MB binaries are NOT committed to git -- files/
# only carries build-qemu10.sh. CI compiles the tarball per build here,
# and the release-files job in .github/data/uploadfiles.yml compiles the
# same tarballs when publishing them as release assets.

set -e

if [ -z "${VM_QEMU_TAR:-}" ]; then
  exit 0
fi
if [ -e "$VM_QEMU_TAR" ]; then
  echo "host_beforeBuild: $VM_QEMU_TAR already present, skipping QEMU build"
  exit 0
fi

# files/qemu-10.2.3-<arch>-noble.tar.zst -> <arch>
base=$(basename "$VM_QEMU_TAR")
arch=$(echo "$base" | sed -nE 's/^qemu-[0-9.]+-([a-z0-9]+)-noble\.tar\.zst$/\1/p')
if [ -z "$arch" ]; then
  echo "host_beforeBuild: cannot derive arch from VM_QEMU_TAR=$VM_QEMU_TAR" >&2
  exit 1
fi

echo "host_beforeBuild: building $VM_QEMU_TAR (arch $arch)"
bash files/build-qemu10.sh "$arch"
test -e "$VM_QEMU_TAR"
