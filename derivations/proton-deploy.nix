{
  coreutils,
  jq,
  nixos-anywhere,
  nixos-rebuild,
  openssh,
  rage,
  writeShellApplication,
}:
writeShellApplication {
  name = "proton-deploy";
  runtimeInputs = [
    # GNU cut, install, mktemp, and chmod for the install verb's staging tree.
    # Their long options do not exist in the macOS versions.
    coreutils
    jq
    # The install verb wraps nixos-anywhere.
    nixos-anywhere
    nixos-rebuild
    openssh
    # Decrypts the pre-generated host key for the install verb.
    rage
  ];
  text = builtins.readFile ../scripts/proton-deploy;
}
