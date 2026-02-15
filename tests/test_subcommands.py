"""Subcommand invocation and error handling tests."""

import pytest

SUBCOMMANDS = ["claude", "codex", "gemini", "ralphex"]


@pytest.mark.parametrize("tool", SUBCOMMANDS)
def test_subcommand_invokes_tool(yolo_cmd, tool):
    """Each yolo subcommand's --help output contains the tool name."""
    result = yolo_cmd(tool, "--help", check=False)
    assert result.returncode == 0, (
        f"'{tool} --help' exited with {result.returncode}: {result.stderr}"
    )
    combined = result.stdout + result.stderr
    assert tool in combined.lower(), f"Expected '{tool}' in output, got: {combined}"


def test_no_args_prints_usage(yolo_cmd):
    """yolo with no args prints usage and exits non-zero."""
    result = yolo_cmd(check=False)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "usage" in combined.lower(), f"Expected usage message, got: {combined}"


def test_run_no_command_prints_usage(yolo_cmd):
    """yolo run with no command prints usage and exits non-zero."""
    result = yolo_cmd("run", check=False)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "usage" in combined.lower(), f"Expected usage message, got: {combined}"


def test_invalid_subcommand_prints_usage(yolo_cmd):
    """yolo invalidcmd prints usage and exits non-zero."""
    result = yolo_cmd("invalidcmd", check=False)
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "usage" in combined.lower(), f"Expected usage message, got: {combined}"
