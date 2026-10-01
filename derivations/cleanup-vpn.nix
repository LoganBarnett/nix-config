{
  bash,
  coreutils,
  procps,
  writeShellApplication,
  ...
}:

writeShellApplication {
  name = "cleanup-vpn";
  runtimeInputs = [
    bash
    coreutils
    procps
  ];
  text = builtins.readFile ../scripts/cleanup-vpn;
}
