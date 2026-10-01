{
  bash,
  bind,
  coreutils,
  curl,
  findutils,
  gawk,
  gnugrep,
  gnused,
  inetutils,
  jq,
  nettools,
  openssh,
  procps,
  writeShellApplication,
  ...
}:

writeShellApplication {
  name = "test-vpn-connectivity";
  runtimeInputs = [
    bash
    # dig lives in the dnsutils output, not the default one.
    bind.dnsutils
    coreutils
    curl
    findutils
    gawk
    gnugrep
    gnused
    inetutils
    jq
    nettools
    openssh
    procps
  ];
  text = builtins.readFile ../scripts/test-vpn-connectivity;
}
