{
  coreutils,
  git,
  jq,
  openssh,
  writeShellApplicationWithLibs,
}:
writeShellApplicationWithLibs {
  name = "gitea-github-sync";
  libs.BASH_LOGGING = ../../bash-logging;
  runtimeInputs = [
    coreutils
    git
    jq
    openssh
  ];
  text = builtins.readFile ./gitea-github-sync;
}
