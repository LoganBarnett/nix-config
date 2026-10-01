{
  bash,
  coreutils,
  gawk,
  gnugrep,
  inetutils,
  killall,
  nettools,
  writeShellApplication,
  ...
}:

writeShellApplication {
  name = "vpn-test-harness-recover";
  runtimeInputs = [
    bash
    coreutils
    gawk
    gnugrep
    inetutils
    killall
    nettools
  ];
  text = builtins.readFile ../scripts/vpn-test-harness-recover;
}
