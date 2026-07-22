# in-guest postBuild hook (piped to the guest's sh over SSH by build.py).
#
# Keep everything tolerant: build.py runs this over the remote shell with
# the remote shell exiting non-zero on any unhandled error, and one dnf
# hiccup should not abort the whole build.

echo "=================== openeuler postBuild ===="

# Make sure sshd survives the reboot that build.py does right after this
# hook (openEuler VM images ship it enabled; this is belt-and-suspenders).
echo "--- enabling sshd.service ---"
systemctl enable sshd.service 2>/dev/null || systemctl enable sshd 2>/dev/null || true

# NOTE: do NOT run "cloud-init clean" here even if cloud-init is present.
# build.py reboots right after this hook, and a clean makes cloud-init
# treat the next boot as a new instance, which (via ssh_deletekeys)
# regenerates the SSH host keys. The host key for the VM's IP then changes
# mid-build and the next "ssh" fails with "REMOTE HOST IDENTIFICATION HAS
# CHANGED".

passwd -d root

echo "openeuler postBuild done."

exit 0
