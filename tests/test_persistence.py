"""Parameterized state persistence tests for the yolo sandbox."""

import uuid

import pytest

PERSISTENCE_PATHS = [
    ".claude",
    ".codex",
    ".gemini",
    ".config/ralphex",
    ".config/gh",
    ".local/share/containers",
]


@pytest.mark.parametrize("rel_path", PERSISTENCE_PATHS)
def test_state_persists(yolo, home_path, rel_path):
    """State written in one sandbox run persists across runs."""
    marker = home_path / rel_path / f"{uuid.uuid4()}"
    result = yolo("test", "-e", marker, check=False)
    assert result.returncode != 0, "Marker should not exist before creation"
    yolo("touch", marker)
    result = yolo("test", "-e", marker, check=False)
    assert result.returncode == 0, "Marker should persist across sandbox runs"
