"""Tests for direnv integration in the yolo sandbox."""

import pytest


@pytest.fixture
def direnv_env(sandbox_env, project_path):
    """Env dict with DIRENV_DIR set, as it would be when a user enters the project dir."""
    return {**sandbox_env, "DIRENV_DIR": f"-{project_path}"}


def test_direnv_loads_if_allowed(yolo, direnv, direnv_env):
    """When .envrc is allowed, envrc variable is exported."""
    direnv("allow", env=direnv_env)
    result = yolo("printenv", "FOO", env=direnv_env, check=False)
    assert result.returncode == 0, "envrc should be loaded"


def test_direnv_skips_when_not_allowed(yolo, direnv, direnv_env, project_path):
    """When .envrc is not allowed, envrc variable is not exported."""
    assert (project_path / ".envrc").exists(), ".envrc file should exist"
    result = yolo("printenv", "FOO", env=direnv_env, check=False)
    assert result.returncode != 0, "envrc should not be loaded"


def test_direnv_skips_when_denied(yolo, direnv, direnv_env):
    """When .envrc is explicitly denied, envrc variable is not exported."""
    direnv("deny", env=direnv_env)
    result = yolo("printenv", "FOO", env=direnv_env, check=False)
    assert result.returncode != 0, "envrc should not be loaded"
