"""Isolation and security boundary tests for the yolo sandbox."""

from __future__ import annotations

import os
import subprocess
import uuid
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable


def test_home_is_isolated(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """Sandbox home contains only the expected directories, nothing from the host."""
    result = yolo("bash", "-c", "ls -1a $HOME")
    actual = set(result.stdout.strip().splitlines())
    expected = {".", "..", ".claude", ".claude.json", ".codex", ".gemini", ".config", ".ssh"}
    # The project dir bind-mount may create intermediate dirs under $HOME
    # (e.g. "dev" if $PWD is /home/user/dev/...).
    cwd = Path.cwd()
    home = Path.home()
    if cwd != home:
        try:
            rel = cwd.relative_to(home)
            expected.add(rel.parts[0])
        except ValueError:
            pass
    assert actual == expected, f"Unexpected home contents: {actual - expected}"


def test_project_dir_is_rw(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """Can create, read, and delete a file in the project directory."""
    marker = f".yolo-test-rw-{uuid.uuid4().hex[:8]}"
    marker_path = Path.cwd() / marker
    try:
        result = yolo(
            "bash",
            "-c",
            f"echo ok > {marker} && cat {marker} && rm {marker}",
        )
        assert result.stdout.strip() == "ok"
    finally:
        if marker_path.exists():
            marker_path.unlink()


def test_host_env_vars_do_not_leak(
    yolo_bin: str,
) -> None:
    """A canary env var set on the host is not visible inside the sandbox."""
    canary = f"YOLO_TEST_CANARY_{uuid.uuid4().hex[:8]}"
    env = {k: v for k, v in os.environ.items() if not k.startswith("DIRENV_")}
    env[canary] = "leaked"
    result = subprocess.run(
        [yolo_bin, "run", "bash", "-c", f"echo ${{{canary}:-NOTSET}}"],
        capture_output=True,
        text=True,
        check=True,
        env=env,
        timeout=60,
    )
    assert result.stdout.strip() == "NOTSET"


def test_clearenv_only_expected_vars(
    yolo: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    """Only expected variables are set inside the sandbox, and all required vars are present."""
    # Variables that must always be present (set by --setenv or /etc/set-environment)
    required_vars = {
        "PATH",
        "HOME",
        "USER",
        "SHELL",
        "TERM",
        "TERMINFO_DIRS",
        "PAGER",
        "LOCALE_ARCHIVE",
        "LANG",
        "NIX_REMOTE",
    }
    # NixOS set-environment exports additional vars beyond our required set
    nixos_vars = {
        "__NIXOS_SET_ENVIRONMENT_DONE",
        "DIRENV_CONFIG",
        "EDITOR",
        "GTK_A11Y",
        "GTK_PATH",
        "INFOPATH",
        "LESSKEYIN_SYSTEM",
        "LIBEXEC_PATH",
        "NIX_PATH",
        "NIX_PROFILES",
        "NIX_USER_PROFILE_DIR",
        "NIXPKGS_CONFIG",
        "NO_AT_BRIDGE",
        "QTWEBKIT_PLUGIN_PATH",
        "SSH_ASKPASS",
        "TZDIR",
        "XCURSOR_PATH",
        "XDG_CONFIG_DIRS",
        "XDG_DATA_DIRS",
    }
    shell_vars = {
        "PWD",
        "SHLVL",
    }
    expected_vars = required_vars | nixos_vars | shell_vars
    result = yolo("env")
    actual_vars = set()
    for line in result.stdout.strip().splitlines():
        if "=" in line:
            var_name = line.split("=", 1)[0]
            actual_vars.add(var_name)
    missing = required_vars - actual_vars
    assert not missing, f"Required env vars missing in sandbox: {missing}"
    unexpected = actual_vars - expected_vars
    assert not unexpected, f"Unexpected env vars in sandbox: {unexpected}"


def test_cannot_write_nix_store(
    yolo: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    """Writing to /nix/store fails inside the sandbox (read-only bind mount)."""
    result = yolo("touch", "/nix/store/yolo-test-file", check=False)
    assert result.returncode != 0


def test_host_tmp_not_visible(
    yolo_bin: str,
) -> None:
    """A marker file in host /tmp is not visible inside the sandbox."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("DIRENV_")}
    marker_name = f".yolo-test-tmp-{uuid.uuid4().hex[:8]}"
    marker_path = Path(f"/tmp/{marker_name}")
    try:
        marker_path.write_text("host-marker")
        cmd = f"test -e /tmp/{marker_name} && echo FOUND || echo NOTFOUND"
        result = subprocess.run(
            [yolo_bin, "run", "bash", "-c", cmd],
            capture_output=True,
            text=True,
            check=True,
            env=env,
            timeout=60,
        )
        assert result.stdout.strip() == "NOTFOUND"
    finally:
        if marker_path.exists():
            marker_path.unlink()


def test_tmp_is_writable(
    yolo: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    """Can create files in /tmp inside the sandbox."""
    result = yolo("bash", "-c", "echo ok > /tmp/yolo-test && cat /tmp/yolo-test")
    assert result.stdout.strip() == "ok"


def test_pid_namespace_isolated(
    yolo: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    """PID namespace is isolated: PID 1 exists and ps output is minimal."""
    result = yolo("bash", "-c", "test -d /proc/1 && echo EXISTS")
    assert result.stdout.strip() == "EXISTS"

    result = yolo("bash", "-c", "ps aux | wc -l")
    line_count = int(result.stdout.strip())
    assert line_count < 20, (
        f"Expected few processes in isolated PID namespace, got {line_count} lines"
    )


def test_project_dir_writes_visible_on_host(
    yolo: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    """A file created inside the sandbox in the project dir is visible on the host."""
    marker = f".yolo-test-host-visible-{uuid.uuid4().hex[:8]}"
    marker_path = Path.cwd() / marker
    try:
        yolo("bash", "-c", f"echo host-check > {marker}")
        assert marker_path.exists(), f"File {marker} should be visible on host"
        assert marker_path.read_text().strip() == "host-check"
    finally:
        if marker_path.exists():
            marker_path.unlink()
