{
  pkgs,
  lib,
  ...
}:
{
  boot.isContainer = true;

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
    less.enable = true;
  };

  environment = {
    enableAllTerminfo = true;

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
