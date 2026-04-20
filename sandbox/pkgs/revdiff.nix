{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "0.21.0";
in
buildGoModule {
  pname = "revdiff";
  inherit version;

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "revdiff";
    tag = "v${version}";
    hash = "sha256-Mqg7lGncMbPx0SfMzDUpG76TwyT2ph1OoZmlswpDLO8=";
  };

  vendorHash = null;

  doCheck = false;

  subPackages = [ "app" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.revision=v${version}"
  ];

  postInstall = ''
    mv $out/bin/app $out/bin/revdiff
  '';

  meta = {
    description = "Terminal UI for reviewing diffs, files, and documents with inline annotations";
    homepage = "https://github.com/umputun/revdiff";
    license = lib.licenses.mit;
    mainProgram = "revdiff";
  };
}
