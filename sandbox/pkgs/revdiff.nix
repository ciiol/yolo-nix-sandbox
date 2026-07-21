{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "1.11.1";
in
buildGoModule {
  pname = "revdiff";
  inherit version;

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "revdiff";
    tag = "v${version}";
    hash = "sha256-C9mquc0mrdFgKN+6YLQJ35Z4DLKNiBxQa2yXa4HXYkI=";
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
