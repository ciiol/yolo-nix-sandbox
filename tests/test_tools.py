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
    "pi",
    "ralphex",
    "revdiff",
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
    "age",
    "sops",
]


@pytest.mark.parametrize("tool", TOOLS)
def test_tool_available(yolo, tool):
    """Each expected tool is available inside the sandbox."""
    result = yolo("which", tool, check=False)
    assert result.returncode == 0, f"Tool '{tool}' not found in sandbox"


def test_claude_has_plugin_wiring(yolo):
    """claude binary is a wrapper that passes --plugin-dir for plugins."""
    result = yolo("bash", "-c", "cat $(which claude)")
    assert "--plugin-dir" in result.stdout
