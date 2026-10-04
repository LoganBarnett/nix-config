{
  coreutils,
  curl,
  jq,
  writeShellApplicationWithLibs,
}:
writeShellApplicationWithLibs {
  name = "gitea-ssh-keys";
  libs.BASH_LOGGING = ../../bash-logging;
  runtimeInputs = [
    coreutils
    curl
    jq
  ];
  text = builtins.readFile ./gitea-ssh-keys;
}
