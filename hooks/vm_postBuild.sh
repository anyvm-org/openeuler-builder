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

# One upstream defect in the shipped /etc/yum.repos.d/*.repo, which costs
# minutes on every build and hits end users inside the VM too:
#
# WRONG EPOL PATH ON riscv64. That image's openEuler.repo sets
#    baseurl=.../EPOL/$basearch/, but the tree lives at
#    .../EPOL/main/$basearch/ -- the x86_64 and aarch64 files get it
#    right, riscv64 does not. The wrong path 404s, which fails the whole
#    metadata refresh and makes every EPOL package uninstallable.
#    fuse-sshfs lives in EPOL, which is why riscv64 looked like it had no
#    sshfs at all; the repo IS published for riscv64
#    (.../EPOL/main/riscv64/repodata/repomd.xml returns 200 and its
#    primary.xml lists fuse-sshfs), the path in the file is just wrong.
#
# The baseurl deliberately stays on the official repo.openeuler.org. It is
# slow (44-193 kB/s of repodata on a GHA runner, ~4m49s of a 13-minute
# build), and mirrors.aliyun.com was tried as a faster stand-in -- but a
# mirror only helps if it is COMPLETE. On 2026-08-31 aliyun's
# openEuler-25.09/everything/aarch64 repomd.xml referenced a
# -primary.xml.zst and a -filelists.xml.zst that both 404 on that mirror,
# so every dnf on that image died (vmactions/openeuler-vm CI). Sweeping 8
# release/arch pairs x 4 repos, aliyun scored 31/32 while
# repo.openeuler.org, repo.huaweicloud.com, tuna, nju and ustc all scored
# 32/32. Correctness before speed: the origin is the one tree guaranteed
# to be self-consistent with what upstream just published.
#
# Character-class forms ([.] [$]) are used instead of backslash escapes
# on purpose: this file travels through several quoting layers before a
# shell in the guest ever sees it, and a swallowed backslash turns a
# back-reference into a control byte that silently corrupts the repo file.
echo "--- repos: fixing the EPOL path ---"
for repofile in /etc/yum.repos.d/*.repo; do
    sed -i 's|/EPOL/[$]basearch/|/EPOL/main/$basearch/|g' "$repofile" 2>/dev/null || true
done

# debuginfo/source (and 22.03's extra update-source) are enabled by
# default but carry nothing this build or a normal VM user installs --
# together 6.3 MB of repodata and ~75 s on every single dnf invocation.
# Disable them; "dnf --enablerepo=debuginfo ..." still works on demand.
# awk, not a sed range: a range ending at a section header never
# terminates for the LAST section in the file, so it would also flip
# whatever follows it.
echo "--- repos: disabling debuginfo/source metadata ---"
for repofile in /etc/yum.repos.d/*.repo; do
    awk '/^[[]/ { sec = $0 } /^enabled=1$/ && (sec == "[debuginfo]" || sec == "[source]" || sec == "[update-source]") { print "enabled=0"; next } { print }' "$repofile" > "$repofile.anyvmnew" 2>/dev/null && mv "$repofile.anyvmnew" "$repofile"
done

# openEuler's shipped /etc/yum.repos.d/*.repo declare BOTH a baseurl and a
# metalink (https://mirrors.openeuler.org/metalink?repo=...). librepo prefers
# the metalink, and the metalink -- not the mirror -- is the authority on the
# expected sha512 of repomd.xml. So whenever the metalink service lags a repo
# republish, EVERY dnf call dies with
#   "Downloading successful, but checksum doesn't match ...
#    Cannot download repomd.xml: All mirrors were tried"
# even though every mirror serves a correct, self-consistent repomd.xml and
# every file it references. Seen 2026-08-30 on the 'update' repo of both
# 22.03-LTS-SP4 and 24.03-LTS-SP4: the mirrors serve repomd sha512 1590d98c...
# while the metalink still demands e3542757.../7bb543ba..., and the metalink
# endpoint itself intermittently 504s. It is NOT a cache problem -- "dnf clean
# all" does not help, because the metalink is refetched every time.
#
# Comment the metalink lines out so dnf falls back to the baseurl, which is
# the plain origin path and is always self-consistent with itself. It also
# pins dnf to that single tree instead of librepo's mirror rotation, so one
# stale or incomplete mirror cannot break a build.
echo "--- disabling metalink= (a stale metalink breaks every dnf) ---"
for repofile in /etc/yum.repos.d/*.repo; do
    sed -i 's/^metalink=/#metalink=/' "$repofile" 2>/dev/null || true
done

echo "--- resulting repo configuration ---"
grep -H -e '^\[' -e '^baseurl=' -e '^enabled=' /etc/yum.repos.d/*.repo 2>/dev/null || true

# NOTE: do NOT run "cloud-init clean" here even if cloud-init is present.
# build.py reboots right after this hook, and a clean makes cloud-init
# treat the next boot as a new instance, which (via ssh_deletekeys)
# regenerates the SSH host keys. The host key for the VM's IP then changes
# mid-build and the next "ssh" fails with "REMOTE HOST IDENTIFICATION HAS
# CHANGED".

passwd -d root

echo "openeuler postBuild done."

exit 0
