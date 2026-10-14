{
  coreutils,
  gnused,
  jq,
  pandoc,
  writeShellApplicationWithLibs,
}:
writeShellApplicationWithLibs {
  name = "nix-options-org";
  libs.BASH_LOGGING = ../../bash-logging;
  runtimeInputs = [
    coreutils
    gnused
    jq
    pandoc
  ];
  text = builtins.readFile ./nix-options-org;
}
