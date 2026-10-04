{
  attic-client,
  attic-server,
  coreutils,
  writeShellApplicationWithLibs,
}:
writeShellApplicationWithLibs {
  name = "attic-watch-store";
  libs.BASH_LOGGING = ../../bash-logging;
  runtimeInputs = [
    attic-client
    attic-server
    coreutils
  ];
  text = builtins.readFile ./attic-watch-store;
}
