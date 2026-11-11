{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "1.15.0";
in
buildGoModule {
  pname = "revdiff";
  inherit version;

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "revdiff";
    tag = "v${version}";
    hash = "sha256-5KJ8q4cDLiFP64iCAt5NvJ9lm4zF9R9snGRiOtxEGis=";
  };

  vendorHash = null;

  doCheck = false;

  subPackages = [ "app/revdiff" ];

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
