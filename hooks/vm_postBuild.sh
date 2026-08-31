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

# Two upstream defects in the shipped /etc/yum.repos.d/*.repo, both of
# which cost minutes on every build and hit end users inside the VM too:
#
# 1. WRONG EPOL PATH ON riscv64. That image's openEuler.repo sets
#    baseurl=.../EPOL/$basearch/, but the tree lives at
#    .../EPOL/main/$basearch/ -- the x86_64 and aarch64 files get it
#    right, riscv64 does not. The wrong path 404s, which fails the whole
#    metadata refresh and makes every EPOL package uninstallable.
#    fuse-sshfs lives in EPOL, which is why riscv64 looked like it had no
#    sshfs at all; the repo IS published for riscv64
#    (.../EPOL/main/riscv64/repodata/repomd.xml returns 200 and its
#    primary.xml lists fuse-sshfs), the path in the file is just wrong.
#
# 2. SLOW ORIGIN. repo.openeuler.org is server-side rate limited: on the
#    GHA runner its repodata came down at 44-193 kB/s, so refreshing the
#    six enabled repos (34.6 MB) burned 4m49s of a 13-minute build --
#    longer than fetching the 940 MB image itself. mirrors.aliyun.com
#    serves the same tree (verified 200 for every repo x arch this
#    builder uses) and is the only mirror with an overseas CDN edge,
#    which is what the US-based CI runners resolve to.
#
# Character-class forms ([.] [$]) are used instead of backslash escapes
# on purpose: this file travels through several quoting layers before a
# shell in the guest ever sees it, and a swallowed backslash turns a
# back-reference into a control byte that silently corrupts the repo file.
echo "--- repos: fixing the EPOL path and switching to mirrors.aliyun.com ---"
for repofile in /etc/yum.repos.d/*.repo; do
    sed -i 's|/EPOL/[$]basearch/|/EPOL/main/$basearch/|g' "$repofile" 2>/dev/null || true
    sed -i 's|^baseurl=https://repo[.]openeuler[.]org/|baseurl=https://mirrors.aliyun.com/openeuler/|' "$repofile" 2>/dev/null || true
    sed -i 's|^baseurl=http://repo[.]openeuler[.]org/|baseurl=https://mirrors.aliyun.com/openeuler/|' "$repofile" 2>/dev/null || true
    sed -i 's|^gpgkey=https://repo[.]openeuler[.]org/|gpgkey=https://mirrors.aliyun.com/openeuler/|' "$repofile" 2>/dev/null || true
    sed -i 's|^gpgkey=http://repo[.]openeuler[.]org/|gpgkey=https://mirrors.aliyun.com/openeuler/|' "$repofile" 2>/dev/null || true
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
# the plain mirror path and is always self-consistent. This also keeps the
# mirror rewrite above effective: a live metalink would send dnf back to the
# slow mirror list regardless of what baseurl says.
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
