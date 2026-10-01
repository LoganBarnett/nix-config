{
  bash,
  bind,
  coreutils,
  dns-resolver-helper,
  dns-vpn-scoping-fix,
  gawk,
  gnugrep,
  gp-connect-auto,
  gpclient,
  jq,
  killall,
  nettools,
  procps,
  writeShellApplication,
  ...
}:
let
  name = "gp-monitor";
  script = name;
in
writeShellApplication {
  inherit name;
  runtimeInputs = [
    bash
    bind.dnsutils
    coreutils
    dns-resolver-helper
    dns-vpn-scoping-fix
    gawk
    gnugrep
    gp-connect-auto
    gpclient
    jq
    killall
    nettools
    procps
  ];
  text = builtins.readFile ../scripts/${script};
}
