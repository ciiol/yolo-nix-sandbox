# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Commands

Run all checks (linters + unit tests + integration tests):

```
just check
```

Format code

```
just fmt
```

## Key Constraints

- Linux only
- Tests require a running Nix daemon, bwrap user namespaces
- The Rust binary cannot run outside `nix develop` or `nix build` because the `SANDBOX_*` env vars must point to valid Nix store paths

## Code Comments

- **Explain "why", not "what".** A comment should provide reasoning, intent, or context that isn't obvious from the code itself. Do not restate what the code does.
- **Prefer naming over comments.** If a comment can be eliminated by renaming a variable, function, or extracting a well-named helper — do that instead.
- **No section-header comments.** Do not use decorative separators like `# --- Section Name ---` to organize code. Use module structure (separate files/classes) and descriptive names instead.
- **TODOs are fine** when they reference a concrete issue or condition for removal (e.g., `# TODO: remove once upstream PR #123 lands`).
- **Configuration grouping comments are acceptable** in flat lists (e.g., package lists in Nix files) where there is no structural alternative.
