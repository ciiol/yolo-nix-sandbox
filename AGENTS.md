# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project Overview

Yolo is a bubblewrap-based sandbox for running commands in an isolated NixOS-like environment. It uses `bwrap` to create a lightweight container with a NixOS system profile, isolated home directory, and read-write access to the current project directory.

## Architecture

- **`flake.nix`** - Nix flake with self-contained output blocks. The `packages` block builds a NixOS system profile (`sandboxConfig`) and packages the `yolo` script (with `@SANDBOX_PROFILE@`, `@SANDBOX_ETC@`, and `@SANDBOX_ENTRYPOINT@` placeholders replaced by Nix store paths) and the `sandbox-entrypoint` script (as a plain `writeShellApplication`), exporting only `packages.default = yolo`. A shared `treefmtEval` function (in the top-level `let`) is called from both `formatter` and `checks` outputs — all linters (nixfmt, shfmt, shellcheck, deadnix, statix, mdformat, ruff-check, ruff-format) are configured as treefmt-nix programs with auto-discovery. Also exports `devShells.default` (just, pytest) and `homeManagerModules.default` (imports the HM module with the flake's `yolo` as the default package).
- **`sandbox.nix`** - NixOS module that defines the sandbox system profile: enabled programs (bash, git, direnv/nix-direnv), system packages, environment variables (TERM, SHELL), nix settings, man page infrastructure, and `/etc/uv/uv.toml` config. System packages include core CLI tools, search/navigation (ripgrep, fd, fzf), text/data processing (jq, gawk), GitHub CLI, networking (curl, wget, dnsutils), database clients (sqlite, postgresql), `uv` package manager, and Python 3 with scientific/data libraries (numpy, pandas, scipy, matplotlib, requests, beautifulsoup4, lxml, scikit-learn, sympy, pillow, openpyxl, pyyaml, httpx). Most environment variables (PATH, LANG, PAGER, NIX_REMOTE, TERMINFO_DIRS, LOCALE_ARCHIVE) are set automatically by NixOS modules and exported via `/etc/set-environment`.
- **`entrypoint.bash`** - Sandbox entrypoint script that sources `/etc/set-environment` to set up the environment, then either wraps the command with `direnv exec .` (when `--direnv` flag is passed) or directly execs it. Packaged as `sandbox-entrypoint` and referenced via its direct Nix store path (`@SANDBOX_ENTRYPOINT@`), not through the system profile.
- **`yolo.bash`** - Bash script (template) that generates minimal `/etc` files at runtime, then `exec`s into `bwrap` with namespace isolation (IPC, PID, UTS). The sandbox profile is bind-mounted to `/run/current-system/sw` so NixOS profile-relative paths resolve correctly. Uses `--clearenv` with only HOME and USER as `--setenv` flags; all other environment variables are set by `sandbox-entrypoint` sourcing `/etc/set-environment`. The current working directory is bind-mounted read-write; home is a tmpfs. When the host's direnv loaded the current directory's `.envrc` (`DIRENV_DIR` matches `-$PWD`), the entrypoint is invoked with `--direnv` to load the project's dev shell inside the sandbox.
- **`modules/home-manager.nix`** - Home Manager module providing `programs.yolo.enable` and `programs.yolo.package` options. When enabled, adds the yolo package to `home.packages`. The flake's `homeManagerModules.default` wraps this module and sets the default package via `self.packages`.
- **`justfile`** - Task runner with targets: `check` (lint + test), `lint` (`nix flake check`), `fmt` (`nix fmt`), `test` (`pytest tests/ -v`).
- **`pyproject.toml`** - Python tooling configuration for pytest and ruff.
- **`tests/`** - Pytest integration test suite:
  - `conftest.py` — shared fixtures (`yolo_bin`, `yolo`, `yolo_cmd`, `yolo_with_state`, `yolo_with_direnv`)
  - `test_basic.py` — basic command execution and exit code propagation
  - `test_isolation.py` — environment, filesystem, and namespace isolation
  - `test_tools.py` — parameterized tool availability checks
  - `test_persistence.py` — state persistence across sandbox runs
  - `test_environment.py` — terminfo, locale, SSL, /etc, man pages, uv config, and nix integration
  - `test_python.py` — Python scientific/data library import checks
  - `test_subcommands.py` — subcommand dispatch and error handling
  - `test_direnv.py` — direnv integration (devshell tool availability, sandbox tool preservation)

## Commands

Enter the dev shell (provides `just`, `pytest`):

```
nix develop
```

Run all checks (lint + test):

```
just check
```

Lint (runs `nix flake check` — all linters via treefmt-nix):

```
just lint
```

Format code (runs `nix fmt` — all formatters and linters via treefmt-nix):

```
just fmt
```

Run tests:

```
just test          # runs pytest tests/ -v
```

Run a command in the sandbox:

```
yolo run <cmd> [args...]
```

## Key Constraints

- Linux only (x86_64 and aarch64)
- Tests require a running Nix daemon, bwrap user namespaces, and network access
- The `yolo.bash` script is a template: `@SANDBOX_PROFILE@`, `@SANDBOX_ETC@`, and `@SANDBOX_ENTRYPOINT@` are replaced at build time by `writeShellApplication` in flake.nix, so the raw script cannot be run directly

## Code Comments

- **Explain "why", not "what".** A comment should provide reasoning, intent, or context that isn't obvious from the code itself. Do not restate what the code does.
- **Prefer naming over comments.** If a comment can be eliminated by renaming a variable, function, or extracting a well-named helper — do that instead.
- **No section-header comments.** Do not use decorative separators like `# --- Section Name ---` to organize code. Use module structure (separate files/classes) and descriptive names instead.
- **TODOs are fine** when they reference a concrete issue or condition for removal (e.g., `# TODO: remove once upstream PR #123 lands`).
- **Configuration grouping comments are acceptable** in flat lists (e.g., package lists in Nix files) where there is no structural alternative.
