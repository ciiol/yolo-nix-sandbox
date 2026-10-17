{
  stdenvNoCC,
  revmux,
}:
stdenvNoCC.mkDerivation {
  pname = "revmux-plugin";
  inherit (revmux) version src;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r .claude-plugin $out/
    runHook postInstall
  '';

  meta = {
    description = "Claude Code plugin for revmux";
    inherit (revmux.meta) homepage license;
  };
}
