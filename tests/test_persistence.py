"""Parameterized state persistence tests for the yolo sandbox."""

import pytest

PERSISTENCE_CASES = [
    ("claude", "~/.claude/marker"),
    ("codex", "~/.codex/marker"),
    ("gemini", "~/.gemini/marker"),
    ("ralphex", "~/.config/ralphex/marker"),
    ("gh", "~/.config/gh/marker"),
    ("containers", "~/.local/share/containers/marker"),
]


@pytest.mark.parametrize(
    ("name", "marker_path"),
    PERSISTENCE_CASES,
    ids=[c[0] for c in PERSISTENCE_CASES],
)
def test_state_persists(yolo_with_state, name, marker_path):
    """State written in one sandbox run persists across runs via XDG_DATA_HOME."""
    content = f"{name}-persistence-marker"
    yolo_with_state("bash", "-c", f"echo '{content}' > {marker_path}")
    result = yolo_with_state("bash", "-c", f"cat {marker_path}")
    assert result.stdout.strip() == content, (
        f"Expected '{content}' in {marker_path}, got '{result.stdout.strip()}'"
    )
