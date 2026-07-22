#!/bin/bash
# host-side prepareImage hook (runs in main process env after _prep_vhd_disk
# materialized "${VM_OS_NAME}.qcow2" but BEFORE the VM is started).
#
# openEuler VM images ship a preset root password (documented upstream as
# "openEuler12#$"), but we do not depend on it: bake our own root password
# and SSH access straight into the qcow2 with virt-customize, so once the
# VM boots we can just ssh in via the slirp hostfwd port (see
# host_enablessh.sh). No console typing, no cloud-init seed disk.

set -e

# build.py writes the working image under build/ (VM_WORK_QCOW); fall back to
# the repo-root name for a standalone hook run.
_qcow="${VM_WORK_QCOW:-${VM_OS_NAME}.qcow2}"

echo "Preparing ${_qcow} with virt-customize"

# Generate the build's SSH keypair now so we can inject its public key into
# the image. build.py would otherwise create the same key later; reuse it.
if [ ! -e "$HOME/.ssh/id_rsa" ]; then
  ssh-keygen -f "$HOME/.ssh/id_rsa" -q -N ""
fi
_pub="$HOME/.ssh/id_rsa.pub"

# libguestfs on a GitHub-hosted runner needs the direct backend.
export LIBGUESTFS_BACKEND=direct
if ! command -v virt-customize >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y libguestfs-tools
fi
# Make the host kernel readable for the libguestfs appliance (harmless if it
# is already readable / not present).
sudo chmod 0644 /boot/vmlinuz-* 2>/dev/null || true

_pw="${VM_ROOT_PASSWORD:-anyvm.org}"

# Everything below is FILESYSTEM-level so the SAME command also works when
# we customize an aarch64 / loongarch64 image on this x86 runner. We
# deliberately avoid --run-command, which has to execute a binary INSIDE
# the guest and fails cross-arch ("host cpu (x86_64) and guest arch (...)
# are not compatible"). --no-network disables the libguestfs appliance
# network (newer libguestfs defaults it on and tries to start "passt",
# which fails on the GitHub-hosted runner).
#
# Access is granted by the injected root key. We append PermitRootLogin etc.
# to the main sshd_config so our appended lines are the first (and only)
# active match and win.
#
# SELinux: an openEuler image that ships SELinux enforcing would deny sshd
# read access to the virt-customize-injected authorized_keys (no proper
# security label), silently failing every pubkey login. WRITE a permissive
# config instead of --edit-ing the existing one: the 25.09 VM image ships
# NO /etc/selinux/config at all (--edit hard-fails on it), while LTS images
# may ship one; writing the standard file covers both (it is inert when
# SELinux is not installed). --mkdir first for the no-selinux-dir case.
#
# The cloud.cfg.d write pins cloud-init (present on some openEuler VM
# images) to the no-op datasources so first boot never stalls probing for
# EC2-style metadata; --mkdir first makes it a no-op when the image has no
# cloud-init at all.
sudo -E virt-customize --no-network -a "${_qcow}" \
  --root-password "password:$_pw" \
  --ssh-inject "root:file:$_pub" \
  --append-line '/etc/ssh/sshd_config:PermitRootLogin yes' \
  --append-line '/etc/ssh/sshd_config:PubkeyAuthentication yes' \
  --append-line '/etc/ssh/sshd_config:AcceptEnv *' \
  --mkdir '/etc/selinux' \
  --write '/etc/selinux/config:SELINUX=permissive
SELINUXTYPE=targeted' \
  --mkdir '/etc/cloud/cloud.cfg.d' \
  --write '/etc/cloud/cloud.cfg.d/99-anyvm-ds.cfg:datasource_list: [ NoCloud, None ]'

# Make sure qemu can read+write the image on the following steps.
sudo chmod 0666 "${_qcow}" 2>/dev/null || true

echo "Image prepared:"
ls -lh "${_qcow}"
