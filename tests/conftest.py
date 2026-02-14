"""Shared pytest fixtures for yolo sandbox integration tests."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Callable

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _env_without_direnv() -> dict[str, str]:
    """Return a copy of os.environ with all DIRENV_* variables removed."""
    return {k: v for k, v in os.environ.items() if not k.startswith("DIRENV_")}


@pytest.fixture(scope="session")
def yolo_bin() -> str:
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
def yolo(yolo_bin: str) -> Callable[..., subprocess.CompletedProcess[str]]:
    """Run commands inside the sandbox via ``yolo run``.

    Strips DIRENV_* vars so host direnv state doesn't affect isolation tests.
    """
    env = _env_without_direnv()

    def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [yolo_bin, "run", *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=60,
        )

    return run


@pytest.fixture
def yolo_cmd(yolo_bin: str) -> Callable[..., subprocess.CompletedProcess[str]]:
    """Run yolo subcommands (no implicit ``run`` prefix).

    Strips DIRENV_* vars so host direnv state doesn't affect subcommand tests.
    """
    env = _env_without_direnv()

    def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [yolo_bin, *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=60,
        )

    return run


@pytest.fixture
def yolo_with_state(
    yolo_bin: str, tmp_path: Path
) -> Callable[..., subprocess.CompletedProcess[str]]:
    """Run commands in the sandbox with a dedicated XDG_DATA_HOME for state persistence.

    Strips DIRENV_* vars so host direnv state doesn't affect persistence tests.
    """
    state_dir = tmp_path / "yolo-state"
    state_dir.mkdir()

    def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        env = {**_env_without_direnv(), "XDG_DATA_HOME": str(state_dir)}
        return subprocess.run(
            [yolo_bin, "run", *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=60,
        )

    return run


@pytest.fixture
def yolo_with_direnv(
    yolo_bin: str,
) -> Callable[..., subprocess.CompletedProcess[str]]:
    """Run commands inside the sandbox with direnv activation.

    Sets DIRENV_DIR to trigger direnv detection in yolo.bash.
    Uses a longer timeout (120s) since the first nix eval in the sandbox may
    need to evaluate the flake.
    """
    env = {**_env_without_direnv(), "DIRENV_DIR": f"-{PROJECT_ROOT}"}

    def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [yolo_bin, "run", *args],
            capture_output=True,
            text=True,
            check=check,
            env=env,
            timeout=120,
        )

    return run
