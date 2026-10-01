{
  bash,
  coreutils,
  dns-resolver-helper,
  gawk,
  gnugrep,
  jq,
  writeShellApplication,
  ...
}:

# Script to fix GlobalProtect VPN DNS scoping on macOS.
# Creates /etc/resolver entries for VPN domains using privileged helper.
writeShellApplication {
  name = "dns-vpn-scoping-fix";
  runtimeInputs = [
    bash
    coreutils
    dns-resolver-helper
    gawk
    gnugrep
    jq
  ];
  text = builtins.readFile ../scripts/dns-vpn-scoping-fix;
}
