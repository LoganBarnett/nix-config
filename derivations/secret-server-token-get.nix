{
  coreutils,
  curl,
  jq,
  writeShellApplicationWithLibs,
}:
writeShellApplicationWithLibs {
  name = "secret-server-token-get";
  libs.BASH_LOGGING = ../bash-logging;
  runtimeInputs = [
    coreutils
    curl
    jq
  ];
  text = builtins.readFile ../scripts/secret-server-token-get;
}
