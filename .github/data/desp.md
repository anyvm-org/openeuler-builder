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
