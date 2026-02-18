"""Environment configuration tests for the yolo sandbox."""

import os

import pytest


def test_terminfo_dirs_set(yolo):
    """$TERMINFO_DIRS is non-empty inside the sandbox."""
    result = yolo("bash", "-c", 'echo "$TERMINFO_DIRS"')
    assert result.stdout.strip(), "TERMINFO_DIRS should be set and non-empty"


def test_terminfo_database_exists(yolo):
    """At least one directory in $TERMINFO_DIRS exists."""
    result = yolo(
        "bash",
        "-c",
        'IFS=:; for d in $TERMINFO_DIRS; do [ -d "$d" ] && echo EXISTS && exit; done; echo MISSING',
    )
    assert result.stdout.strip() == "EXISTS", "At least one TERMINFO_DIRS entry should exist"


def test_terminfo_xterm_entry(yolo):
    """An xterm terminfo entry exists in one of the $TERMINFO_DIRS directories."""
    cmd = (
        "IFS=:; for d in $TERMINFO_DIRS; do"
        ' [ -e "$d/x/xterm" ] && echo EXISTS && exit;'
        " done; echo MISSING"
    )
    result = yolo("bash", "-c", cmd)
    assert result.stdout.strip() == "EXISTS", "xterm terminfo entry should exist"


def test_locale_archive_set(yolo):
    """$LOCALE_ARCHIVE is non-empty inside the sandbox."""
    result = yolo("bash", "-c", 'echo "$LOCALE_ARCHIVE"')
    assert result.stdout.strip(), "LOCALE_ARCHIVE should be set and non-empty"


def test_lang_is_utf8(yolo):
    """$LANG equals C.UTF-8 (set by i18n.defaultLocale in sandbox.nix via set-environment)."""
    result = yolo("bash", "-c", 'echo "$LANG"')
    assert result.stdout.strip() == "C.UTF-8"


def test_term_matches_host_or_fallback(yolo):
    """TERM inside sandbox matches host TERM, falling back to xterm-256color."""
    host_val = os.environ.get("TERM")
    expected = host_val if host_val else "xterm-256color"
    result = yolo("bash", "-c", 'echo "$TERM"')
    sandbox_val = result.stdout.strip()
    assert sandbox_val == expected, f"Sandbox TERM={sandbox_val!r} should be {expected!r}"


@pytest.mark.parametrize("var", ["COLORTERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION"])
def test_optional_terminal_var_matches_host(yolo, var):
    """Optional terminal env vars inside sandbox match host values (passthrough via bwrap)."""
    host_val = os.environ.get(var)
    if host_val:
        result = yolo("bash", "-c", f'echo "${{{var}:-}}"')
        sandbox_val = result.stdout.strip()
        assert sandbox_val == host_val, (
            f"Sandbox {var}={sandbox_val!r} should match host {var}={host_val!r}"
        )
    else:
        cmd = f'if [ -n "${{{var}+set}}" ]; then echo "SET:${{{var}}}"; else echo UNSET; fi'
        result = yolo("bash", "-c", cmd)
        sandbox_state = result.stdout.strip()
        assert sandbox_state == "UNSET", (
            f"Sandbox {var} should be unset when host has no value, got {sandbox_state!r}"
        )


def test_shell_is_bash(yolo):
    """$SHELL points to bash (set via environment.variables in sandbox.nix)."""
    result = yolo("bash", "-c", 'echo "$SHELL"')
    assert result.stdout.strip().endswith("/bash")


def test_locale_no_warnings(yolo):
    """The locale command produces no stderr."""
    result = yolo("locale")
    assert result.stderr == "", f"locale should produce no stderr, got: {result.stderr}"


def test_ssl_certs_present(yolo):
    """/etc/ssl/certs/ca-certificates.crt contains BEGIN CERTIFICATE."""
    result = yolo("bash", "-c", "grep -c 'BEGIN CERTIFICATE' /etc/ssl/certs/ca-certificates.crt")
    count = int(result.stdout.strip())
    assert count > 0, "SSL certificate bundle should contain at least one certificate"


def test_nix_store_visible(yolo):
    """ls /nix/store produces non-empty output."""
    result = yolo("ls", "/nix/store")
    assert result.stdout.strip(), "/nix/store should have contents"


def test_nix_daemon_reachable(yolo):
    """nix store info succeeds, confirming the daemon is reachable."""
    result = yolo("nix", "store", "info", check=False)
    assert result.returncode == 0, f"nix store info failed: {result.stderr}"


def test_passwd_has_three_lines(yolo):
    """/etc/passwd has exactly 3 lines."""
    result = yolo("bash", "-c", "wc -l < /etc/passwd")
    line_count = int(result.stdout.strip())
    assert line_count == 3, f"Expected 3 lines in /etc/passwd, got {line_count}"


def test_passwd_contains_current_user(yolo):
    """/etc/passwd contains the current username."""
    result = yolo("bash", "-c", 'grep -c "^$USER:" /etc/passwd')
    count = int(result.stdout.strip())
    assert count >= 1, "/etc/passwd should contain the current username"


def test_uv_config_content(yolo):
    """/etc/uv/uv.toml contains the only-system python preference."""
    result = yolo("cat", "/etc/uv/uv.toml")
    assert 'python-preference = "only-system"' in result.stdout


def test_man_page_lookup(yolo):
    """man can locate a specific page, confirming man pages and caches are available."""
    result = yolo("man", "-w", "bash", check=False)
    assert result.returncode == 0, f"man -w bash failed: {result.stderr}"
    assert result.stdout.strip(), "man -w bash should return a path"
