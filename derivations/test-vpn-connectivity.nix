{
  bash,
  bind,
  coreutils,
  curl,
  gnugrep,
  inetutils,
  jq,
  nettools,
  openssh,
  writeShellApplication,
  ...
}:

writeShellApplication {
  name = "test-vpn-connectivity";
  runtimeInputs = [
    bash
    bind
    coreutils
    curl
    gnugrep
    inetutils
    jq
    nettools
    openssh
  ];
  text = builtins.readFile ../scripts/test-vpn-connectivity;
}
