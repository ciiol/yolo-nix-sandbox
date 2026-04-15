{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "revdiff";
  version = "0.18.0";

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "revdiff";
    tag = "v${version}";
    hash = "sha256-6S+saZoVn7notatueMsYRLrz/cQzLDRYcutlqOaMad4=";
  };

  vendorHash = null;

  doCheck = false;

  subPackages = [ "app" ];

  postInstall = ''
    mv $out/bin/app $out/bin/revdiff
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.revision=v${version}"
  ];

  meta = {
    description = "Terminal UI for reviewing diffs, files, and documents with inline annotations";
    homepage = "https://github.com/umputun/revdiff";
    license = lib.licenses.mit;
    mainProgram = "revdiff";
  };
}
