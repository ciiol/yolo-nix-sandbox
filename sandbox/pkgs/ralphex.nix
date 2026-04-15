{
  lib,
  buildGo126Module,
  fetchFromGitHub,
}:
buildGo126Module rec {
  pname = "ralphex";
  version = "0.26.1";

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "ralphex";
    tag = "v${version}";
    hash = "sha256-5JODDSGGR6JKN6YJmt1rVPFNTe0hQ/UaqjfMNB3yyE0=";
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
