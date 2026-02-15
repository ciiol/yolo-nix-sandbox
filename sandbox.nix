{
  pkgs,
  lib,
  ...
}:
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
      nix-direnv.enable = true;
    };
    less.enable = true;
  };

  environment = {
    variables.TERM = "xterm-256color";
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
      ncurses
      coreutils
      bashInteractive
      gnugrep
      gnused
      findutils
      nix
      cacert
      curl
      claude-code
      codex
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

  system.stateVersion = "26.05";
}
