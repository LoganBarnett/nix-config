{
  bash,
  bind,
  coreutils,
  inetutils,
  jq,
  writeShellApplication,
  ...
}:

writeShellApplication {
  name = "vpn-test-harness";
  runtimeInputs = [
    bash
    bind
    coreutils
    inetutils
    jq
  ];
  text = builtins.readFile ../scripts/vpn-test-harness;
}
