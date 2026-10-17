{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "0.2.6";
in
buildGoModule {
  pname = "revmux";
  inherit version;

  src = fetchFromGitHub {
    owner = "umputun";
    repo = "revmux";
    tag = "v${version}";
    hash = "sha256-h5uBAnIJf/rpTkOC/k9ihyhjBc2j4VZfFv3tkhyXHBs=";
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
    mv $out/bin/app $out/bin/revmux
  '';

  meta = {
    description = "Supervised multi-agent code review with parallel claude and codex subprocesses";
    homepage = "https://github.com/umputun/revmux";
    license = lib.licenses.mit;
    mainProgram = "revmux";
  };
}
