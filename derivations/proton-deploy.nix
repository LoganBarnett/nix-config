{
  jq,
  nixos-rebuild,
  openssh,
  writeShellApplication,
}:
writeShellApplication {
  name = "proton-deploy";
  runtimeInputs = [
    jq
    openssh
    nixos-rebuild
  ];
  text = builtins.readFile ../scripts/proton-deploy;
}
