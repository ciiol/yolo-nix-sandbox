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


def _env_without_direnv():
    """Return a copy of os.environ with all DIRENV_* variables removed."""
    return {k: v for k, v in os.environ.items() if not k.startswith("DIRENV_")}


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
def yolo(yolo_bin):
    """Run commands inside the sandbox via ``yolo run``.

    Strips DIRENV_* vars so host direnv state doesn't affect isolation tests.
    """
    env = _env_without_direnv()

    def run(*args, check=True, timeout=60):
        return subprocess.run(
            [yolo_bin, "run", *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=timeout,
        )

    return run


@pytest.fixture
def yolo_cmd(yolo_bin):
    """Run yolo subcommands (no implicit ``run`` prefix).

    Strips DIRENV_* vars so host direnv state doesn't affect subcommand tests.
    """
    env = _env_without_direnv()

    def run(*args, check=True, timeout=60):
        return subprocess.run(
            [yolo_bin, *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=timeout,
        )

    return run


@pytest.fixture
def yolo_with_state(yolo_bin, tmp_path):
    """Run commands in the sandbox with a dedicated XDG_DATA_HOME for state persistence.

    Strips DIRENV_* vars so host direnv state doesn't affect persistence tests.
    """
    state_dir = tmp_path / "yolo-state"
    state_dir.mkdir()

    def run(*args, check=True):
        env = {**_env_without_direnv(), "XDG_DATA_HOME": str(state_dir)}
        return subprocess.run(
            [yolo_bin, "run", *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=120,
        )

    return run


@pytest.fixture
def yolo_with_direnv(yolo_bin, tmp_path):
    """Run commands inside the sandbox with direnv activation.

    Sets DIRENV_DIR to trigger direnv detection and creates a proper "allowed"
    state via ``direnv allow .`` with an isolated XDG_DATA_HOME so the host's
    allow database is not consulted.
    """
    state_dir = tmp_path / "direnv-allowed"
    state_dir.mkdir()
    allow_env = {**os.environ, "XDG_DATA_HOME": str(state_dir)}
    subprocess.run(
        ["direnv", "allow", "."],
        cwd=PROJECT_ROOT,
        env=allow_env,
        check=True,
        capture_output=True,
    )
    env = {
        **_env_without_direnv(),
        "DIRENV_DIR": f"-{PROJECT_ROOT}",
        "XDG_DATA_HOME": str(state_dir),
    }

    def run(*args, check=True):
        return subprocess.run(
            [yolo_bin, "run", *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=120,
        )

    return run


@pytest.fixture
def yolo_with_direnv_denied(yolo_bin, tmp_path):
    """Run commands inside the sandbox with direnv detection but .envrc explicitly denied.

    Uses a fresh XDG_DATA_HOME and runs ``direnv deny .`` so direnv records
    AllowStatus 2 (Denied) for the project .envrc.
    """
    state_dir = tmp_path / "direnv-denied"
    state_dir.mkdir()
    deny_env = {**os.environ, "XDG_DATA_HOME": str(state_dir)}
    subprocess.run(
        ["direnv", "deny", "."],
        cwd=PROJECT_ROOT,
        env=deny_env,
        check=True,
        capture_output=True,
    )
    env = {
        **_env_without_direnv(),
        "DIRENV_DIR": f"-{PROJECT_ROOT}",
        "XDG_DATA_HOME": str(state_dir),
    }

    def run(*args, check=True):
        return subprocess.run(
            [yolo_bin, "run", *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=120,
        )

    return run


@pytest.fixture
def yolo_with_direnv_not_allowed(yolo_bin, tmp_path):
    """Run commands inside the sandbox with direnv detection but .envrc NOT allowed.

    Uses a fresh XDG_DATA_HOME so direnv has no allow/deny record for the .envrc,
    resulting in AllowStatus 1 (NotAllowed).
    """
    state_dir = tmp_path / "direnv-not-allowed"
    state_dir.mkdir()
    env = {
        **_env_without_direnv(),
        "DIRENV_DIR": f"-{PROJECT_ROOT}",
        "XDG_DATA_HOME": str(state_dir),
    }

    def run(*args, check=True):
        return subprocess.run(
            [yolo_bin, "run", *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=120,
        )

    return run
