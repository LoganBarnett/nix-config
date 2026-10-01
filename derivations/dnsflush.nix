{
  coreutils,
  killall,
  writeShellApplication,
}:
writeShellApplication {
  name = "dnsflush";
  runtimeInputs = [
    coreutils
    killall
  ];
  # The script uses non-portable arithmetic syntax that shellcheck rejects.
  checkPhase = "";
  text = builtins.readFile ../scripts/dnsflush;
}
