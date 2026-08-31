# In-guest install script for openeuler (piped into the guest sh by
# build.py with ANYVM_PKGS prepended; runs under set -e).
#
# Skip the `everything` repo at BUILD time. A package audit of a real
# build shows every package this builder installs comes from OS (17 of
# them) or EPOL (fuse-sshfs) -- not one from `everything`, whose metadata
# alone is 16 MB and took 2m24s of a 4m33s dnf step on the CI runner.
#
# The fallback is load-bearing, not cosmetic: if a package added to
# VM_PRE_INSTALL_PKGS later DOES live only in `everything`, the first
# command fails and the second one installs it, instead of the build
# dying on "No match for argument". Wrapping the first call in `if` is
# what keeps its failure from tripping the enclosing `set -e`.
#
# Only this build-time install is narrowed. The shipped image keeps
# `everything` enabled, so end users still see the full package set.
if dnf install -y --disablerepo=everything $ANYVM_PKGS; then
    exit 0
fi
echo "install without the 'everything' repo failed; retrying with all repos"
dnf install -y $ANYVM_PKGS
