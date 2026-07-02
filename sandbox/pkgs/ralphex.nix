{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "1.6.0";
in
buildGoModule {
  pname = "ralphex";
  inherit version;

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "ralphex";
    tag = "v${version}";
    hash = "sha256-RUl5BVGc5EjeXZNjfC2WVZrrSXxR1mQyABkIxIT2NyQ=";
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
