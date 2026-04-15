{
  pkgs,
  lib,
  ...
}:
let
  # Codex v0.115.0+ uses bwrap internally, which rejects non-zero ambient caps.
  # In wide-UID mode yolo grants CAP_SETUID/CAP_SETGID inside the sandbox,
  # so we must clear them before codex spawns its own bwrap.
  codex-wrapped = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      exec ${pkgs.util-linux}/bin/setpriv --ambient-caps -all -- ${pkgs.codex}/bin/codex "$@"
    '';
  };
in
{
  boot.isContainer = true;

  documentation.man = {
    enable = true;
    generateCaches = true;
  };

  i18n.defaultLocale = "C.UTF-8";

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

  programs = {
    bash = {
      enable = true;
      completion.enable = true;
    };
    git = {
      enable = true;
      lfs.enable = true;
    };
    direnv = {
      enable = true;
      silent = true;
      nix-direnv.enable = true;
    };
    less.enable = true;
  };

  environment = {
    enableAllTerminfo = true;
    variables.SHELL = "/run/current-system/sw/bin/bash";

    etc."uv/uv.toml".source =
      let
        tomlFormat = pkgs.formats.toml { };
      in
      tomlFormat.generate "uv-config" {
        python-preference = "only-system";
      };

    systemPackages = with pkgs; [
      # Core
      coreutils
      pkgsStatic.busybox
      bashInteractive
      gnugrep
      gnused
      findutils
      nix
      cacert
      curl
      claude-code
      codex-wrapped
      gemini-cli
      ralphex

      # Search & navigation
      ripgrep
      fd
      tree
      which
      file
      fzf

      # Text & data processing
      jq
      gawk
      diffutils
      gnupatch

      # GitHub & collaboration
      gh
      openssh

      # Security & encryption
      age
      sops

      # Archives & compression
      gnutar
      gzip
      xz
      zip
      unzip

      # Build tools
      gnumake

      # System inspection
      procps

      # Network
      wget
      dnsutils

      # Database clients
      sqlite
      postgresql

      # Containers
      podman-compose

      # Package management
      uv

      # Python (scientific/data)
      (python3.withPackages (
        ps: with ps; [
          numpy
          pandas
          scipy
          matplotlib
          requests
          beautifulsoup4
          lxml
          scikit-learn
          sympy
          pillow
          openpyxl
          pyyaml
          httpx
        ]
      ))
    ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  virtualisation.containers = {
    enable = true;
    containersConf.settings.engine.cgroup_manager = "cgroupfs";
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  system.stateVersion = "26.05";
}
