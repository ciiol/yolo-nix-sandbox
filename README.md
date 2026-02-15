# Yolo

A bubblewrap-based sandbox for running commands in an isolated NixOS-like
environment. Yolo uses `bwrap` to create a lightweight container with a NixOS
system profile, isolated home directory, and read-write access to the current
project directory.

## Key Features

- **Shared Nix store and daemon** — the sandbox bind-mounts `/nix/store`
  (read-only) and the daemon socket (read-write), so all cached packages are
  available and builds go through the host daemon.
- **Ephemeral by default** — home directory is temporary, environment variables are cleared
  and rebuilt from a NixOS profile. Each run starts clean.
- **Selective state persistence** — specific config directories survive across
  sessions via `$XDG_DATA_HOME/yolo/`: git config, SSH known hosts and allowed
  signers, GitHub CLI auth, and AI coding agent state.

## Quick Start

Run Claude inside the sandbox:

```sh
nix run github:ciiol/yolo-nix-sandbox -- claude
```

Or an arbitrary command:

```sh
nix run github:ciiol/yolo-nix-sandbox -- run git status
```

## Installation

### NixOS with Home Manager (flake)

Add yolo as a flake input and enable the Home Manager module:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    yolo.url = "github:ciiol/yolo-nix-sandbox";
    yolo.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      yolo,
      ...
    }:
    {
      nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [ yolo.homeManagerModules.default ];
            home-manager.users.jdoe = {
              programs.yolo.enable = true;
            };
          }
        ];
      };
    };
}
```

## Usage

Yolo provides several subcommands:

```sh
yolo run <cmd> [args...]   # Run an arbitrary command in the sandbox
yolo claude [args...]      # Run Claude Code in the sandbox
yolo codex [args...]       # Run Codex in the sandbox
yolo gemini [args...]      # Run Gemini in the sandbox
yolo ralphex [args...]     # Run Ralphex in the sandbox
```

The sandbox mounts the current working directory read-write, so your project
files are accessible. The home directory is isolated, and IPC, PID, and
UTS namespaces are unshared.

If the host's direnv has loaded the current directory's `.envrc`, yolo
automatically activates the project's dev shell inside the sandbox.

## Security Model

The sandbox is designed to prevent **accidental** damage to the host and **accidental**
secret exposure.

It is **not a security boundary**. In particular:

- The network is fully shared, so sandboxed processes can reach any host or
  service the host can.
- The project directory is mounted read-write, so a sandboxed process can modify
  or add files there.
- A carefully crafted payload can escape via the Nix daemon (which has full host
  store access) or by placing malicious artifacts in the project directory that
  execute outside the sandbox later.

Treat yolo as a guardrail against mistakes, not as a defense against malicious
code.

## Development

Enter the dev shell:

```sh
nix develop
```

Available commands (via `just`):

```sh
just check   # Run lint + test
just lint    # Run nix flake check (all linters via treefmt-nix)
just fmt     # Run nix fmt (all formatters via treefmt-nix)
just test    # Run pytest tests/ -v
```

## Requirements

- Linux only (x86_64 and aarch64)
- Running Nix daemon
- User namespaces enabled (for bubblewrap)
