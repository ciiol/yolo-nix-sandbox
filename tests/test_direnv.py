"""Tests for direnv integration in the yolo sandbox."""


def test_direnv_loads_devshell_tools(yolo_with_direnv):
    """With direnv active, devShell tools (e.g. just) are available."""
    result = yolo_with_direnv("bash", "-c", "command -v just", check=False)
    assert result.returncode == 0, f"'just' not found with direnv active: {result.stderr}"


def test_direnv_preserves_sandbox_tools(yolo_with_direnv):
    """With direnv active, sandbox tools (e.g. jq) are still available."""
    result = yolo_with_direnv("bash", "-c", "command -v jq", check=False)
    assert result.returncode == 0, f"'jq' not found with direnv active: {result.stderr}"


def test_direnv_inactive_without_host_direnv(yolo):
    """Without DIRENV_DIR set, devShell tools are NOT available (proving they come from direnv)."""
    result = yolo("bash", "-c", "command -v just", check=False)
    assert result.returncode != 0, "'just' should not be available without direnv"
