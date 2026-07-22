#!/bin/bash
# host-side waitForLoginTag override (called from start_and_wait after
# startVM + openConsole, before the default waitForText fires).
#
# The openEuler VM image boots to a serial getty, but the arch/console
# plumbing makes OCR/console-text matching fragile (especially under
# aarch64 / loongarch64 TCG). Since prepareImage already baked SSH access
# into the qcow2, we poll the slirp hostfwd port on 127.0.0.1:$VM_SSH_PORT
# until sshd actually answers.
#
# IMPORTANT: do NOT probe with a bare TCP connect (e.g. `echo > /dev/tcp/...`).
# slirp's `hostfwd` makes QEMU listen on the HOST port the moment it starts,
# completing the host-side 3-way handshake well before the guest kernel has
# even POSTed. A bare TCP probe therefore returns "open" immediately and we
# fall through to the real ssh phase against a guest that's nowhere near up.
# Probe with `ssh ... exit` so the test only succeeds when the GUEST sshd
# actually answers (which under TCG on a 2-core GHA runner can take 10-20
# minutes after QEMU launch).

set -u

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=10
  -o BatchMode=yes
  -p "${VM_SSH_PORT}"
)

# build.py writes the serial log under build/ (exported as VM_WORKDIR);
# fall back to the repo root for a standalone hook run.
SERIAL_LOG="${VM_WORKDIR:+$VM_WORKDIR/}${VM_OS_NAME:-openeuler}.serial.log"
QEMU_PID_FILE="${VM_WORKDIR:+$VM_WORKDIR/}${VM_OS_NAME:-openeuler}.pid"

_n=0
# 240 iters * (timeout 30 + sleep 10) = up to ~2.5 h worst case; on KVM this
# returns in seconds. The big ceiling is for cold TCG aarch64/loongarch64
# boots on a 2-core GHA runner.
while [ "$_n" -lt 240 ]; do
  # Fail FAST when QEMU itself died (crashed / was killed): waiting the
  # full ssh ceiling against a dead VM wastes hours. A crashed QEMU shows
  # up as a zombie (build.py has not reaped it) or the pid is gone. The
  # non-zero exit is fatal via run_hook's host-hook rc check.
  _qp=$(cat "$QEMU_PID_FILE" 2>/dev/null)
  if [ -n "$_qp" ]; then
    _qstate=$(ps -o stat= -p "$_qp" 2>/dev/null)
    case "$_qstate" in
      ""|Z*)
        echo "QEMU (pid $_qp) is dead (state '${_qstate:-gone}'); aborting the ssh wait"
        echo "--- qemu log tail ---"
        tail -20 "${VM_WORKDIR:+$VM_WORKDIR/}${VM_OS_NAME:-openeuler}.qemu.log" 2>/dev/null
        exit 1
        ;;
    esac
  fi
  if timeout 30 ssh "${SSH_OPTS[@]}" "root@127.0.0.1" exit >/dev/null 2>&1; then
    echo "sshd is answering ssh on 127.0.0.1:${VM_SSH_PORT}"
    break
  fi
  # Every 6 iterations (~1 minute), dump the last 10 lines of the guest
  # serial log so we can see how far the boot got -- "still in EDK2",
  # "stuck in dracut", "kernel panic", etc. Without this the wait is
  # opaque and indistinguishable from a dead VM.
  if [ $((_n % 6)) -eq 0 ] && [ -f "$SERIAL_LOG" ]; then
    echo "--- serial log tail (iter $_n) ---"
    # -a forces grep to treat the file as text. Without it, the embedded
    # ANSI escape / NUL bytes from the serial chardev make grep think the
    # input is binary and emit "binary file matches" instead of the
    # filtered lines. The leading tr strips C0 control bytes (except CR/LF
    # which we still need for line splitting) so the eventual line stream
    # is clean enough to read in CI logs.
    tail -c 8192 "$SERIAL_LOG" \
      | tr -d '\000\001\002\003\004\005\006\007\010\013\014\016\017\020\021\022\023\024\025\026\027\030\031\032\034\035\036\037' \
      | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r/\n/g' \
      | grep -av '^[[:space:]]*$' \
      | tail -10
    echo "--- end serial tail ---"
  fi
  echo "waiting for VM sshd on 127.0.0.1:${VM_SSH_PORT} (iter $_n) ..."
  sleep 10
  _n=$((_n + 1))
done

sleep 5
