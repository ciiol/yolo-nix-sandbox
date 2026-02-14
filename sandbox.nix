{
  pkgs,
  lib,
  ...
}:
{
  boot.isContainer = true;

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
    enableAllTerminfo = true;
    variables.TERM = "xterm-256color";
    variables.SHELL = "/run/current-system/sw/bin/bash";

    systemPackages = with pkgs; [
      # Core
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
    ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.05";
}
