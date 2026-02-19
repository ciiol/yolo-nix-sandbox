"""Parameterized tool availability tests for the yolo sandbox."""

import pytest

TOOLS = [
    "jq",
    "rg",
    "fd",
    "gh",
    "git",
    "make",
    "ssh",
    "less",
    "tar",
    "claude",
    "codex",
    "gemini",
    "ralphex",
    "direnv",
    "man",
    "dig",
    "sqlite3",
    "psql",
    "uv",
    "python3",
    "podman",
    "podman-compose",
    "docker",
    "busybox",
]


@pytest.mark.parametrize("tool", TOOLS)
def test_tool_available(yolo, tool):
    """Each expected tool is available inside the sandbox."""
    result = yolo("which", tool, check=False)
    assert result.returncode == 0, f"Tool '{tool}' not found in sandbox"
