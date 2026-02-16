# AGENTS.md

This file provides guidance to agents when working with code in this repository.

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
just test
```

Run a command in the sandbox:

```
yolo run <cmd> [args...]
```

## Key Constraints

- Linux only
- Tests require a running Nix daemon, bwrap user namespaces
- The `yolo.bash` script is a template: `@SANDBOX_PROFILE@`, `@SANDBOX_ETC@`, and `@SANDBOX_ENTRYPOINT@` are replaced at build time by `writeShellApplication` in flake.nix, so the raw script cannot be run directly

## Code Comments

- **Explain "why", not "what".** A comment should provide reasoning, intent, or context that isn't obvious from the code itself. Do not restate what the code does.
- **Prefer naming over comments.** If a comment can be eliminated by renaming a variable, function, or extracting a well-named helper — do that instead.
- **No section-header comments.** Do not use decorative separators like `# --- Section Name ---` to organize code. Use module structure (separate files/classes) and descriptive names instead.
- **TODOs are fine** when they reference a concrete issue or condition for removal (e.g., `# TODO: remove once upstream PR #123 lands`).
- **Configuration grouping comments are acceptable** in flat lists (e.g., package lists in Nix files) where there is no structural alternative.
