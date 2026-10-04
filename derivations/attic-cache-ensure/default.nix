{
  attic-server,
  coreutils,
  curl,
  jq,
  writeShellApplicationWithLibs,
}:
writeShellApplicationWithLibs {
  name = "attic-cache-ensure";
  libs.BASH_LOGGING = ../../bash-logging;
  runtimeInputs = [
    attic-server
    coreutils
    curl
    jq
  ];
  text = builtins.readFile ./attic-cache-ensure;
}
