

[![Build](https://github.com/anyvm-org/openeuler-builder/actions/workflows/build.yml/badge.svg)](https://github.com/anyvm-org/openeuler-builder/actions/workflows/build.yml)

Latest: v2.0.2


The image builder for `openeuler`


All the supported releases are here:



| Release | x86_64 (amd64) | aarch64 (arm64) | riscv64 | loongarch64 |
|---------|---------|---------|---------|---------|
| 25.09 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,nfs,tar) | — |
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
https://www.openeuler.org/en/download/).




How to build:

1. Use the [manual.yml](.github/workflows/manual.yml) to build manually.
   
    Run the workflow manually, you will get a view-only webconsole from the output of the workflow, just open the link in your web browser.
   
    You will also get an interactive VNC connection port from the output, you can connect to the vm by any vnc client.

2. Run the builder locally on your Ubuntu machine.

    Just clone the repo. and run:
    ```bash
    python3 build.py conf/openeuler-25.09.conf
    ```
   
