# files/

## build-qemu10.sh

Builds the pinned QEMU 10.2.3 tarball(s) from source on an ubuntu-24.04
(noble) host. Adapted from `ubuntu-builder/files/build-qemu10.sh` (which
pins riscv64 / s390x / ppc64le for the Ubuntu guests); this copy adds the
`loongarch64` target.

Why loongarch64 is pinned at all: the noble runner's stock QEMU 8.2 ships
`qemu-system-loongarch64`, but NOT the bundled EDK2 LoongArch UEFI firmware
(`edk2-loongarch64-code.fd` / `edk2-loongarch64-vars.fd`). QEMU only started
bundling that firmware pair in 9.2, and the loongarch `virt` machine cannot
boot a UEFI disk image (the openEuler loongarch64 qcow2) without it.

The tarball (`qemu-10.2.3-loongarch64-noble.tar.zst`, ~30MB) is NOT
committed to git:

- during an image build, `hooks/host_beforeBuild.sh` compiles it on the fly
  when the conf sets `VM_QEMU_TAR`;
- at release time, the `release-files` job (see
  `.github/data/uploadfiles.yml`) compiles it and uploads it as a release
  asset, which is where anyvm's runtime (`ensure_pinned_qemu`) downloads it
  from for end users whose system QEMU is older than 9.2.
