{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "1.7.0";
in
buildGoModule {
  pname = "ralphex";
  inherit version;

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "ralphex";
    tag = "v${version}";
    hash = "sha256-fwbT23wzJrc7ljI4R2Lmdf0q0Y0/DeBbYYt2WMN/67A=";
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
