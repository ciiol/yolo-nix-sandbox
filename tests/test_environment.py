"""Environment configuration tests for the yolo sandbox."""

import os
import pwd
from pathlib import Path

import pytest


def test_terminfo_dirs_set(yolo):
    """$TERMINFO_DIRS is non-empty inside the sandbox."""
    result = yolo("printenv", "TERMINFO_DIRS")
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
    result = yolo("printenv", "LOCALE_ARCHIVE")
    assert result.stdout.strip(), "LOCALE_ARCHIVE should be set and non-empty"


def test_lang_is_utf8(yolo):
    """$LANG equals C.UTF-8 (set by i18n.defaultLocale in sandbox.nix via set-environment)."""
    result = yolo("printenv", "LANG")
    assert result.stdout.strip() == "C.UTF-8"


def test_term_matches_host_or_fallback(yolo, sandbox_env):
    """TERM inside sandbox matches the env passed to yolo, falling back to xterm-256color."""
    # bash auto-sets TERM=dumb when it's absent from the environment
    result = yolo("printenv", "TERM")
    assert result.stdout.strip() == "dumb"

    env = {**sandbox_env, "TERM": "xterm-kitty"}
    result = yolo("printenv", "TERM", env=env)
    assert result.stdout.strip() == "xterm-kitty"


@pytest.mark.parametrize("var", ["COLORTERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION"])
def test_optional_terminal_var_matches_host(yolo, sandbox_env, var):
    """Optional terminal env vars are passed through when set, absent when not."""
    result = yolo("printenv", var, check=False)
    assert result.returncode != 0, f"Sandbox {var} should be unset with default sandbox_env"

    test_value = "test-value"
    env = {**sandbox_env, var: test_value}
    result = yolo("printenv", var, env=env)
    assert result.stdout.strip() == test_value, (
        f"Sandbox {var} should be {test_value!r} when set in env"
    )


def test_pi_skips_version_check_by_default(yolo):
    """Default config wraps pi to skip its (unactionable) version check, stays online."""
    script = yolo("bash", "-c", 'cat "$(command -v pi)"').stdout
    assert "PI_SKIP_VERSION_CHECK" in script
    assert "PI_OFFLINE" not in script


def test_shell_is_bash(yolo):
    """$SHELL points to bash (set via environment.variables in sandbox.nix)."""
    result = yolo("printenv", "SHELL")
    assert result.stdout.strip().endswith("/bash")


def test_locale_no_warnings(yolo):
    """The locale command produces no stderr."""
    result = yolo("locale")
    assert result.stderr == "", f"locale should produce no stderr, got: {result.stderr}"


def test_ssl_certs_present(yolo):
    """/etc/ssl/certs/ca-certificates.crt contains BEGIN CERTIFICATE."""
    result = yolo("grep", "-c", "BEGIN CERTIFICATE", "/etc/ssl/certs/ca-certificates.crt")
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


def test_nix_search_path_has_no_missing_entries(yolo):
    """A search path lookup that misses nixpkgs evaluates without warnings."""
    result = yolo(
        "nix-instantiate", "--eval", "--expr", "(builtins.tryEval <nixpkgs-overlays>).success"
    )
    assert result.stdout.strip() == "false"
    assert "warning" not in result.stderr, result.stderr


def test_passwd_has_three_lines(yolo):
    """/etc/passwd has exactly 3 lines."""
    result = yolo("wc", "-l", "/etc/passwd")
    line_count = int(result.stdout.strip().split()[0])
    assert line_count == 3, f"Expected 3 lines in /etc/passwd, got {line_count}"


def test_passwd_contains_current_user(yolo):
    """/etc/passwd contains the current username."""
    user = pwd.getpwuid(os.getuid()).pw_name
    result = yolo("grep", "-c", f"^{user}:", "/etc/passwd")
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


def test_usr_bin_env_exists(yolo):
    """/usr/bin/env is a symlink into the Nix store and is executable."""
    target = yolo("readlink", "/usr/bin/env").stdout.strip()
    assert target.startswith("/nix/store/"), f"expected /nix/store/ target, got {target!r}"
    assert target.endswith("/bin/env"), f"expected .../bin/env, got {target!r}"
    yolo("test", "-x", "/usr/bin/env")


def test_usr_bin_env_runs_shebang(yolo, project_path):
    """A `#!/usr/bin/env sh` shebang script runs successfully."""
    script = project_path / "script.sh"
    script.write_text("#!/usr/bin/env sh\necho ok\n")
    script.chmod(0o755)
    result = yolo(str(script))
    assert result.stdout.strip() == "ok"


def test_bin_sh_exists(yolo):
    """/bin/sh is a symlink into the Nix store and is executable."""
    target = yolo("readlink", "/bin/sh").stdout.strip()
    assert target.startswith("/nix/store/"), f"expected /nix/store/ target, got {target!r}"
    assert target.endswith("/bin/sh"), f"expected .../bin/sh, got {target!r}"
    yolo("test", "-x", "/bin/sh")


def test_bin_sh_runs_shebang(yolo, project_path):
    """A `#!/bin/sh` shebang script runs successfully."""
    script = project_path / "script.sh"
    script.write_text("#!/bin/sh\necho ok\n")
    script.chmod(0o755)
    result = yolo(str(script))
    assert result.stdout.strip() == "ok"


def test_run_binfmt_mounted_readonly(yolo):
    """Host /run/binfmt (binfmt interpreter links) is visible in the sandbox."""
    if not Path("/run/binfmt").is_dir():
        pytest.skip("host has no /run/binfmt")
    yolo("test", "-d", "/run/binfmt")
    options = yolo("findmnt", "-n", "-o", "OPTIONS", "/run/binfmt").stdout.strip()
    assert "ro" in options.split(","), f"expected read-only mount, got {options!r}"


def test_binfmt_misc_mounted_readonly(yolo):
    """Host binfmt_misc status is readable in the sandbox through a read-only mount."""
    if not Path("/proc/sys/fs/binfmt_misc/status").exists():
        pytest.skip("host has no mounted binfmt_misc")
    status = yolo("cat", "/proc/sys/fs/binfmt_misc/status").stdout.strip()
    assert status in ("enabled", "disabled"), f"unexpected binfmt_misc status {status!r}"
    options = yolo("findmnt", "-n", "-o", "OPTIONS", "/proc/sys/fs/binfmt_misc").stdout.strip()
    assert "ro" in options.split(","), f"expected read-only mount, got {options!r}"
