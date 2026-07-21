{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "1.6.1";
in
buildGoModule {
  pname = "ralphex";
  inherit version;

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "ralphex";
    tag = "v${version}";
    hash = "sha256-M1VeZgpNv64ZbcNvhzscnhTJhuR6yrh+clAWAce7vxI=";
  };

  vendorHash = null;

  doCheck = false;

  subPackages = [ "cmd/ralphex" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.revision=v${version}"
  ];

  meta = {
    description = "Autonomous AI plan executor using Claude Code";
    homepage = "https://github.com/umputun/ralphex";
    license = lib.licenses.mit;
    mainProgram = "ralphex";
  };
}
