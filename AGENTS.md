# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project Overview

Yolo is a bubblewrap-based sandbox for running commands in an isolated NixOS-like environment. It uses `bwrap` to create a lightweight container with a NixOS system profile, isolated home directory, and read-write access to the current project directory.

## Architecture

- **`flake.nix`** - Nix flake that builds a NixOS system profile (`sandboxConfig`) and packages the `yolo` script with `@SANDBOX_PROFILE@` and `@SANDBOX_ETC@` placeholders replaced by Nix store paths. Uses treefmt-nix for `formatter` and `checks` outputs.
- **`yolo.sh`** - Bash script (template) that generates minimal `/etc` files at runtime, then `exec`s into `bwrap` with namespace isolation (IPC, PID, UTS). The current working directory is bind-mounted read-write; home is a tmpfs.
- **`tests/test-poc.sh`** - Integration tests that build yolo via `nix build`, then verify sandbox behavior (isolation, networking, nix daemon access, exit code propagation).

## Commands

Enter the dev shell (provides `yolo`, `just`):
```
nix develop
```

Run all checks (lint + test):
```
just check
```

Lint (runs `nix flake check` — shellcheck, statix, deadnix, formatting):
```
just lint
```

Format code (runs `nix fmt` — nixfmt + shfmt):
```
just fmt
```

Run tests:
```
just test          # runs tests/test-poc.sh
```

Run a command in the sandbox:
```
yolo run <cmd> [args...]
```

## Key Constraints

- x86_64-linux only (hardcoded in flake.nix)
- Tests require a running Nix daemon and network access (they test `curl` to github.com and `nix build nixpkgs#hello`)
- The `yolo.sh` script is a template: `@SANDBOX_PROFILE@` and `@SANDBOX_ETC@` are replaced at build time by `writeShellApplication` in flake.nix, so the raw script cannot be run directly
