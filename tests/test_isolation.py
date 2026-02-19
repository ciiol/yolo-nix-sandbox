"""Isolation and security boundary tests for the yolo sandbox."""

import contextlib
import os
import selectors
import signal
import subprocess
import time
import uuid
from pathlib import Path

import pytest


def test_home_is_isolated(yolo, home_path):
    """A file created in HOME on the host is not visible inside the sandbox."""
    marker = home_path / f"{uuid.uuid4()}"
    marker.touch(exist_ok=False)
    result = yolo("test", "-e", marker, check=False)
    assert result.returncode != 0, "Host-side HOME file should not be visible in sandbox"


def test_project_dir_transparent(yolo, project_path):
    """Sandbox can see changes in project directory and is able to change it."""
    marker = project_path / f"{uuid.uuid4()}"
    marker.touch(exist_ok=False)
    result = yolo("test", "-e", marker, check=False)
    assert result.returncode == 0, "File created in project directory should be visible in sandbox"
    result = yolo("rm", marker, check=False)
    assert result.returncode == 0, "Sandbox should be able to delete files in project directory"
    assert not marker.exists(), "File deleted inside sandbox should be deleted on host"


def test_host_env_vars_do_not_leak(yolo, sandbox_env):
    """A canary env var set on the host is not visible inside the sandbox."""
    canary = f"YOLO_TEST_CANARY_{uuid.uuid4().hex[:8]}"
    env = {**sandbox_env, canary: "leaked"}
    result = yolo("printenv", canary, env=env, check=False)
    assert result.returncode != 0, (
        f"Expected printenv to fail (variable not found), got exit code {result.returncode}"
    )
    assert result.stdout == "", (
        f"Expected no output from printenv for a missing variable, got: {result.stdout!r}"
    )
    assert result.stderr == "", (
        f"Expected no stderr (wrapper failure would produce stderr), got: {result.stderr!r}"
    )


def test_cannot_write_nix_store(yolo):
    """Writing to /nix/store fails inside the sandbox (read-only bind mount)."""
    result = yolo("touch", "/nix/store/yolo-test-file", check=False)
    assert result.returncode != 0


def test_host_tmp_not_visible(yolo):
    """A marker file in host /tmp is not visible inside the sandbox."""
    marker_name = f".yolo-test-tmp-{uuid.uuid4().hex[:8]}"
    marker_path = Path(f"/tmp/{marker_name}")
    try:
        marker_path.touch(exist_ok=False)
        result = yolo("test", "-e", f"/tmp/{marker_name}", check=False)
        assert result.returncode != 0, "Marker in host /tmp should not be visible in sandbox"
    finally:
        if marker_path.exists():
            marker_path.unlink()


def test_tmp_is_writable(yolo):
    """Can create files in /tmp inside the sandbox."""
    marker = f"/tmp/.yolo-test-tmp-{uuid.uuid4().hex[:8]}"
    result = yolo("test", "-e", marker, check=False)
    assert result.returncode != 0, "Marker should not exist before test"
    result = yolo("touch", marker, check=False)
    assert result.returncode == 0, "Should be able to create files in /tmp inside sandbox"


def test_pid_namespace_isolated(yolo):
    """PID namespace is isolated"""
    result = yolo("ps", "aux", "--no-headers")
    line_count = len(result.stdout.splitlines())
    assert line_count == 2, f"Expected few processes, got {line_count}: {result.stdout}"


def test_sigwinch_delivered(yolo_bin, sandbox_env):
    """SIGWINCH sent from the host reaches the sandbox process."""
    # The script traps SIGWINCH, signals readiness, then waits for the signal.
    script = (
        "trap 'echo SIGWINCH_RECEIVED; exit 0' WINCH; echo READY; while true; do sleep 0.1; done"
    )
    # Start in its own process group so we can signal the whole group
    # without affecting the test runner.
    proc = subprocess.Popen(
        [yolo_bin, "run", "bash", "-c", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=sandbox_env,
        start_new_session=True,
    )
    try:
        # Wait for the sandbox process to signal readiness (bounded so a
        # broken sandbox startup doesn't hang the entire test suite).
        deadline = time.monotonic() + 30
        sel = selectors.DefaultSelector()
        sel.register(proc.stdout, selectors.EVENT_READ)
        ready = False
        try:
            while time.monotonic() < deadline:
                if sel.select(timeout=max(0, deadline - time.monotonic())):
                    line = proc.stdout.readline()
                    if not line:
                        break
                    if line.strip() == "READY":
                        ready = True
                        break
        finally:
            sel.close()
        assert ready, "Sandbox process never signaled READY"
        # Send SIGWINCH to the process group. Without --new-session in bwrap,
        # the sandboxed process inherits this session and receives the signal.
        os.killpg(proc.pid, signal.SIGWINCH)
        stdout, _ = proc.communicate(timeout=10)
        assert "SIGWINCH_RECEIVED" in stdout
    finally:
        if proc.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()


def test_no_cap_sys_admin(yolo):
    """Sandbox does not have CAP_SYS_ADMIN (bit 21 in CapEff is unset)."""
    result = yolo("bash", "-c", "grep '^CapEff:' /proc/self/status | awk '{print $2}'")
    cap_eff = int(result.stdout.strip(), 16)
    cap_sys_admin = 1 << 21
    assert cap_eff & cap_sys_admin == 0, f"CAP_SYS_ADMIN should not be set, CapEff=0x{cap_eff:016x}"


def test_tiocsctty_rejected(yolo):
    """TIOCSCTTY ioctl fails inside the sandbox (cannot steal controlling terminal)."""
    # TIOCSCTTY = 0x540E on Linux.
    # When run under pipes (no real PTY), /dev/tty won't exist — that also
    # prevents TIOCSCTTY, so we accept both outcomes as "rejected".
    script = "\n".join(
        [
            "import fcntl, os, sys",
            "try:",
            "    fd = os.open('/dev/tty', os.O_RDWR)",
            "except OSError:",
            "    print('NO_TTY')",
            "    sys.exit(0)",
            "try:",
            "    fcntl.ioctl(fd, 0x540E, 0)",
            "    print('ALLOWED')",
            "    sys.exit(1)",
            "except OSError:",
            "    print('REJECTED')",
            "    sys.exit(0)",
            "finally:",
            "    os.close(fd)",
        ]
    )
    result = yolo("python3", "-c", script, check=False)
    output = result.stdout.strip()
    if output == "NO_TTY":
        pytest.skip("No controlling terminal available; TIOCSCTTY path not tested")
    assert output == "REJECTED", f"TIOCSCTTY should be rejected, got: {result.stdout}"
