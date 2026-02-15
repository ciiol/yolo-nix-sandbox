"""Parameterized tool availability tests for the yolo sandbox."""

import pytest

TOOLS = [
    "jq",
    "rg",
    "fd",
    "gh",
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
]


@pytest.mark.parametrize("tool", TOOLS)
def test_tool_available(yolo, tool):
    """Each expected tool is available inside the sandbox."""
    result = yolo("bash", "-c", f"command -v {tool}", check=False)
    assert result.returncode == 0, f"Tool '{tool}' not found in sandbox"


def test_nix_available(yolo):
    """nix is available and reports its version."""
    result = yolo("nix", "--version", check=False)
    assert result.returncode == 0, f"nix --version failed: {result.stderr}"
    assert "nix" in result.stdout.lower(), "Expected 'nix' in version output"
