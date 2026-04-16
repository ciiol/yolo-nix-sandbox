{
  stdenvNoCC,
  ralphex,
}:
stdenvNoCC.mkDerivation {
  pname = "ralphex-plugin";
  inherit (ralphex) version src;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/assets
    cp -r .claude-plugin $out/
    cp -r assets/claude $out/assets/
    runHook postInstall
  '';

  meta = {
    description = "Claude Code plugin for ralphex";
    inherit (ralphex.meta) homepage license;
  };
}
