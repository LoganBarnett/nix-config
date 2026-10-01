{
  bash,
  bind,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  gp-connect-auto,
  gpclient,
  inetutils,
  jq,
  killall,
  nettools,
  procps,
  vpn-test-harness-recover,
  writeShellApplication,
  ...
}:

writeShellApplication {
  name = "vpn-test-harness";
  runtimeInputs = [
    bash
    # dig lives in the dnsutils output, not the default one.
    bind.dnsutils
    coreutils
    gawk
    gnugrep
    gnused
    gp-connect-auto
    gpclient
    inetutils
    jq
    killall
    nettools
    procps
    vpn-test-harness-recover
  ];
  text = builtins.readFile ../scripts/vpn-test-harness;
}
