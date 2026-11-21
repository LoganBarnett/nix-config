{
  agenix-rekey,
  coreutils,
  git,
  jq,
  nix,
  openssh,
  rage,
  writeShellApplication,
}:
writeShellApplication {
  name = "nix-host-new";
  runtimeInputs = [
    agenix-rekey
    coreutils
    git
    jq
    nix
    openssh
    rage
  ];
  text = builtins.readFile ../scripts/nix-host-new;
}
