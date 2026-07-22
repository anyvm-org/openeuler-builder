# Image-slimming finalize. Runs as the LAST in-guest hook, after postBuild
# and the VM_PRE_INSTALL_PKGS dnf installs.
#
# NOTE: only the package archive cache is dropped ("dnf clean packages");
# the repo METADATA is kept so users (and the vmactions VM_PREPARE step)
# can `dnf install` without a full metadata refresh, which is painfully
# slow on the TCG-emulated arches.

echo "=== finalize: image cleanup ==="

# Drop cached .rpm archives fetched by the build's installs.
dnf clean packages || true

# TRIM every mounted filesystem: the build disk runs with discard=unmap,
# so freed blocks (package churn) become holes in the qcow2 and the
# export-time sparsify reclaims them.
fstrim -av || true

df -h || true
echo "=== finalize: image cleanup done ==="
