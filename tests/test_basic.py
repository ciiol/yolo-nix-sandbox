"""Basic command execution and exit code tests."""

from __future__ import annotations

import getpass
import os
import socket
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable


def test_echo(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """yolo run echo hello outputs 'hello'."""
    result = yolo("echo", "hello")
    assert result.stdout.strip() == "hello"


def test_pwd(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """yolo run pwd outputs current working directory."""
    result = yolo("pwd")
    assert result.stdout.strip() == str(Path.cwd())


def test_whoami(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """yolo run whoami outputs current username."""
    result = yolo("whoami")
    assert result.stdout.strip() == getpass.getuser()


def test_id(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """yolo run id -u outputs current uid."""
    result = yolo("id", "-u")
    assert result.stdout.strip() == str(os.getuid())


def test_hostname(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """yolo run hostname outputs host hostname."""
    result = yolo("hostname")
    assert result.stdout.strip() == socket.gethostname()


def test_exit_code_propagation(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """yolo run false returns exit code 1."""
    result = yolo("false", check=False)
    assert result.returncode == 1


def test_nonexistent_command_exit_code(
    yolo: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    """yolo run nonexistent_cmd_xyz returns non-zero exit code."""
    result = yolo("nonexistent_cmd_xyz", check=False)
    assert result.returncode != 0
