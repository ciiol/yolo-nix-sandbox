{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "0.27.3";
in
buildGoModule {
  pname = "ralphex";
  inherit version;

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "ralphex";
    tag = "v${version}";
    hash = "sha256-AA1MJRrrtIohWY85z7k/KeXcsWtMa72/sf9XLWE5O8I=";
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
