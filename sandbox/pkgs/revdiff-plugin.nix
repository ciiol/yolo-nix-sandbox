{
  stdenvNoCC,
  revdiff,
}:
stdenvNoCC.mkDerivation {
  pname = "revdiff-plugin";
  inherit (revdiff) version src;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r .claude-plugin $out
    runHook postInstall
  '';

  meta = {
    description = "Claude Code plugin for revdiff";
    inherit (revdiff.meta) homepage license;
  };
}
