"""Environment configuration tests for the yolo sandbox."""

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable


def test_terminfo_dirs_set(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """$TERMINFO_DIRS is non-empty inside the sandbox."""
    result = yolo("bash", "-c", 'echo "$TERMINFO_DIRS"')
    assert result.stdout.strip(), "TERMINFO_DIRS should be set and non-empty"


def test_terminfo_database_exists(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """At least one directory in $TERMINFO_DIRS exists."""
    result = yolo(
        "bash",
        "-c",
        'IFS=:; for d in $TERMINFO_DIRS; do [ -d "$d" ] && echo EXISTS && exit; done; echo MISSING',
    )
    assert result.stdout.strip() == "EXISTS", "At least one TERMINFO_DIRS entry should exist"


def test_terminfo_xterm_entry(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """An xterm terminfo entry exists in one of the $TERMINFO_DIRS directories."""
    cmd = (
        "IFS=:; for d in $TERMINFO_DIRS; do"
        ' [ -e "$d/x/xterm" ] && echo EXISTS && exit;'
        " done; echo MISSING"
    )
    result = yolo("bash", "-c", cmd)
    assert result.stdout.strip() == "EXISTS", "xterm terminfo entry should exist"


def test_locale_archive_set(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """$LOCALE_ARCHIVE is non-empty inside the sandbox."""
    result = yolo("bash", "-c", 'echo "$LOCALE_ARCHIVE"')
    assert result.stdout.strip(), "LOCALE_ARCHIVE should be set and non-empty"


def test_lang_is_utf8(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """$LANG equals C.UTF-8 (set by i18n.defaultLocale in sandbox.nix via set-environment)."""
    result = yolo("bash", "-c", 'echo "$LANG"')
    assert result.stdout.strip() == "C.UTF-8"


def test_term_is_xterm_256color(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """$TERM equals xterm-256color (set via environment.variables in sandbox.nix)."""
    result = yolo("bash", "-c", 'echo "$TERM"')
    assert result.stdout.strip() == "xterm-256color"


def test_shell_is_bash(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """$SHELL points to bash (set via environment.variables in sandbox.nix)."""
    result = yolo("bash", "-c", 'echo "$SHELL"')
    assert result.stdout.strip().endswith("/bash")


def test_locale_no_warnings(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """The locale command produces no stderr."""
    result = yolo("locale")
    assert result.stderr == "", f"locale should produce no stderr, got: {result.stderr}"


def test_ssl_certs_present(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """/etc/ssl/certs/ca-certificates.crt contains BEGIN CERTIFICATE."""
    result = yolo("bash", "-c", "grep -c 'BEGIN CERTIFICATE' /etc/ssl/certs/ca-certificates.crt")
    count = int(result.stdout.strip())
    assert count > 0, "SSL certificate bundle should contain at least one certificate"


def test_nix_store_visible(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """ls /nix/store produces non-empty output."""
    result = yolo("ls", "/nix/store")
    assert result.stdout.strip(), "/nix/store should have contents"


def test_nix_daemon_reachable(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """nix store info succeeds, confirming the daemon is reachable."""
    result = yolo("nix", "store", "info", check=False)
    assert result.returncode == 0, f"nix store info failed: {result.stderr}"


def test_passwd_has_three_lines(yolo: Callable[..., subprocess.CompletedProcess[str]]) -> None:
    """/etc/passwd has exactly 3 lines."""
    result = yolo("bash", "-c", "wc -l < /etc/passwd")
    line_count = int(result.stdout.strip())
    assert line_count == 3, f"Expected 3 lines in /etc/passwd, got {line_count}"


def test_passwd_contains_current_user(
    yolo: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    """/etc/passwd contains the current username."""
    result = yolo("bash", "-c", 'grep -c "^$USER:" /etc/passwd')
    count = int(result.stdout.strip())
    assert count >= 1, "/etc/passwd should contain the current username"
