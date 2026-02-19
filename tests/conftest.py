"""Shared pytest fixtures for yolo sandbox integration tests."""

import os
import pwd
import shutil
import subprocess
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _get_subid_count(path, user):
    """Return subid count for the last matching entry, or None."""
    p = Path(path)
    if not p.exists():
        return None
    for line in reversed(p.read_text().splitlines()):
        parts = line.split(":")
        if len(parts) == 3 and parts[0] == user:
            return int(parts[2])
    return None


def _host_has_wide_uid():
    """Check if the host has wide-UID support, matching has_wide_uid_support() in yolo.bash."""
    user = pwd.getpwuid(os.getuid()).pw_name
    uid = os.getuid()
    gid = os.getgid()

    uid_count = _get_subid_count("/etc/subuid", user)
    gid_count = _get_subid_count("/etc/subgid", user)
    if uid_count is None or gid_count is None:
        return False

    if not (shutil.which("newuidmap") and shutil.which("newgidmap")):
        return False

    return uid >= 2 and gid >= 2 and uid < uid_count and gid < gid_count


@pytest.fixture(scope="session")
def wide_uid():
    """Session-scoped fixture: True if host has wide-UID prerequisites."""
    return _host_has_wide_uid()


@pytest.fixture
def requires_wide_uid(wide_uid):
    """Skip the test if the host lacks wide-UID support."""
    if not wide_uid:
        pytest.skip("host lacks wide-UID support (subuid/subgid/newuidmap/newgidmap)")


@pytest.fixture(scope="session")
def yolo_bin():
    """Build yolo once per test session, return binary path."""
    try:
        result = subprocess.run(
            ["nix", "build", "--no-link", "--print-out-paths"],
            capture_output=True,
            text=True,
            check=True,
            cwd=PROJECT_ROOT,
            timeout=300,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"nix build failed:\n{e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("nix build timed out after 300 seconds")
    return f"{result.stdout.strip()}/bin/yolo"


@pytest.fixture
def project_path(tmp_path):
    """Creates a temporary directory to use as the project directory for yolo run."""
    dest = tmp_path / "project"
    dest.mkdir()
    return dest


@pytest.fixture
def home_path(tmp_path):
    """Creates a temporary directory to use as the home directory for yolo run."""
    dest = tmp_path / "home"
    dest.mkdir()
    return dest


@pytest.fixture
def sandbox_env(home_path):
    """Minimal env for running yolo. Treat as read-only."""
    return {
        "PATH": os.environ["PATH"],
        "HOME": str(home_path),
    }


@pytest.fixture
def yolo(yolo_cmd, sandbox_env):
    """Run commands inside the sandbox via ``yolo run``.

    Uses sandbox_env by default. Pass ``env=`` to replace with a custom env.
    """

    def run(*args, **kwargs):
        return yolo_cmd("run", *args, **kwargs)

    return run


@pytest.fixture
def yolo_cmd(yolo_bin, project_path, sandbox_env):
    """Run yolo subcommands (no implicit ``run`` prefix).

    Uses sandbox_env by default. Pass ``env=`` to replace with a custom env.
    """

    def run(*args, check=True, timeout=60, env=None):
        return subprocess.run(
            [yolo_bin, *args],
            capture_output=True,
            text=True,
            check=check,
            cwd=project_path,
            env=env or sandbox_env,
            timeout=timeout,
        )

    return run


@pytest.fixture
def direnv(project_path, sandbox_env):
    """Run ``direnv allow/deny .`` using the sandbox_env's XDG_DATA_HOME. Creates dummy .envrc.

    Only handles filesystem setup (the allow database). Tests are responsible
    for adding DIRENV_DIR to the env they pass to yolo.
    """
    envrc_path = project_path / ".envrc"
    envrc_path.write_text("export FOO=bar\n")

    def setup(action, env=None):
        return subprocess.run(
            ["direnv", action, "."],
            cwd=project_path,
            env=env or sandbox_env,
            check=True,
            capture_output=True,
        )

    return setup
