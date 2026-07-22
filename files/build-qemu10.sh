#!/bin/bash
# Build the pinned QEMU 10.2.3 system emulators from source against the
# host distro's libraries and package each as
#   files/qemu-10.2.3-<arch>-noble.tar.zst
# with a pruned, self-contained layout:
#   qemu10-<arch>/bin/qemu-system-<qemu-arch>
#   qemu10-<arch>/share/qemu/<only the firmware that machine type needs>
# (QEMU locates its datadir relative to the binary, so the tree works from
# any extraction directory.)
#
# Usage: bash files/build-qemu10.sh <arch> [<arch> ...]
#   arch: loongarch64 | riscv64 | s390x | ppc64le
# All requested arches are built from ONE configure/make run (combined
# --target-list), then pruned and packaged per arch.
#
# Intended host: ubuntu-24.04 (noble) -- the GitHub Actions runner image,
# which is also the ABI the builder and anyvm's test workflow run on (the
# "noble" in the tarball name). The tarballs are NOT committed to git:
# hooks/host_beforeBuild.sh generates the one a conf needs per build, and
# the release-files job in .github/data/uploadfiles.yml generates them for
# the release assets. See files/README.md for why each arch is pinned.
# (Adapted from ubuntu-builder/files/build-qemu10.sh; this copy adds the
# loongarch64 target openeuler-builder needs.)

set -e

QEMU_VER=10.2.3

if [ $# -lt 1 ]; then
  echo "usage: $0 <arch> [<arch> ...]   (loongarch64 | riscv64 | s390x | ppc64le)" >&2
  exit 1
fi

# arch -> qemu target / binary suffix / extra firmware to keep
qemu_target() {
  case "$1" in
    loongarch64) echo "loongarch64-softmmu" ;;
    riscv64) echo "riscv64-softmmu" ;;
    s390x)   echo "s390x-softmmu" ;;
    ppc64le) echo "ppc64-softmmu" ;;
    *) echo "unknown arch: $1" >&2; return 1 ;;
  esac
}
qemu_binarch() {
  case "$1" in
    ppc64le) echo "ppc64" ;;
    *)       echo "$1" ;;
  esac
}
qemu_firmware() {
  case "$1" in
    # EDK2 UEFI for the loongarch virt machine; QEMU bundles the pair
    # since 9.2 (absent from noble's stock 8.2, the whole reason for
    # this pin).
    loongarch64) echo "edk2-loongarch64-code.fd edk2-loongarch64-vars.fd" ;;
    riscv64) echo "opensbi-riscv64-generic-fw_dynamic.bin" ;;
    # s390-netboot.img is gone in QEMU >= 9.1 (folded into s390-ccw.img)
    s390x)   echo "s390-ccw.img" ;;
    ppc64le) echo "slof.bin vgabios-stdvga.bin" ;;
  esac
}

ARCHES="$*"
TARGETS=""
for a in $ARCHES; do
  t=$(qemu_target "$a")
  TARGETS="${TARGETS:+$TARGETS,}$t"
done

OUT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d /tmp/qemu10-build.XXXXXX)
echo "build dir: $WORK (left in place; /tmp is ephemeral)"

SUDO=sudo
[ "$(id -u)" = 0 ] && SUDO=

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq build-essential ninja-build pkg-config \
  python3-venv libglib2.0-dev libpixman-1-dev libslirp-dev libfdt-dev \
  zlib1g-dev wget xz-utils zstd >/dev/null

cd "$WORK"
wget -q "https://download.qemu.org/qemu-${QEMU_VER}.tar.xz"
tar xf "qemu-${QEMU_VER}.tar.xz"
cd "qemu-${QEMU_VER}"

# Same feature trim as the original container builds: no GUI, no docs, no
# storage/remote backends the builders never use; slirp + VNC + system fdt
# kept (build.py drives guests over user networking and VNC).
./configure --target-list="$TARGETS" --prefix="$WORK/install" \
  --disable-docs --disable-gtk --disable-sdl --disable-opengl \
  --disable-virglrenderer --disable-spice --disable-smartcard \
  --disable-usb-redir --disable-libiscsi --disable-rbd --disable-glusterfs \
  --disable-libnfs --disable-seccomp --disable-linux-aio --disable-libusb \
  --disable-tpm --enable-slirp --enable-vnc --enable-fdt=system \
  > "$WORK/configure.log" 2>&1 || { tail -30 "$WORK/configure.log"; exit 1; }
make -j"$(nproc)" > "$WORK/make.log" 2>&1 || { tail -30 "$WORK/make.log"; exit 1; }
make install > /dev/null

for a in $ARCHES; do
  binarch=$(qemu_binarch "$a")
  root="qemu10-$a"
  pkg="$WORK/pkg-$a"
  mkdir -p "$pkg/$root/bin" "$pkg/$root/share/qemu"
  cp "$WORK/install/bin/qemu-system-$binarch" "$pkg/$root/bin/"
  for f in $(qemu_firmware "$a") efi-virtio.rom; do
    cp "$WORK/install/share/qemu/$f" "$pkg/$root/share/qemu/"
  done
  cp -r "$WORK/install/share/qemu/keymaps" "$pkg/$root/share/qemu/keymaps"

  "$pkg/$root/bin/qemu-system-$binarch" --version | head -1
  out="$OUT_DIR/qemu-${QEMU_VER}-$a-noble.tar.zst"
  tar --zstd -cf "$out" -C "$pkg" "$root"
  ls -la "$out"
  sha256sum "$out"
done

echo "build-qemu10: done ($ARCHES)"
