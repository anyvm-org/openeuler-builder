

| Release | x86_64 (amd64) | aarch64 (arm64) | riscv64 | loongarch64 |
|---------|---------|---------|---------|---------|
| 25.09 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | — |
| 24.03-LTS-SP4 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | — | ✅ (rsync,scp,sshfs,nfs,tar) |
| 22.03-LTS-SP4 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | — | — |

<!-- arch-label: x86_64 = x86_64 (amd64) -->
<!-- arch-label: aarch64 = aarch64 (arm64) -->

How the images are built:

Each image is built automatically in the
[anyvm-org/openeuler-builder](https://github.com/anyvm-org/openeuler-builder)
repo's GitHub Actions: it downloads the official openEuler virtual
machine image, customizes it (serial console, ssh, first-boot setup),
boots it in QEMU, pre-installs the packages listed in the conf, and
exports the disk as a compressed qcow2 image. No interactive installer
is run.

Upstream media: the official openEuler VM images from
https://repo.openeuler.org/ (download page:
https://www.openeuler.org/en/download/). The builder downloads them
from https://mirrors.aliyun.com/openeuler/ and points the guest's dnf
there too: it is a byte-identical mirror, and an order of magnitude
faster from the CI runners than the rate-limited origin.
