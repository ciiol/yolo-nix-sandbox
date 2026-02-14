{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "ralphex";
  version = "0.11.1";

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "ralphex";
    tag = "v${version}";
    hash = "sha256-XzakLhynZQppOgi3lnMif7YTzVdXVNBlDu6omB1zVlE=";
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
