{
  bash,
  coreutils,
  killall,
  writeShellApplication,
  ...
}:

# Privileged helper for managing /etc/resolver DNS configuration.
# This validates all inputs and only operates on /etc/resolver.
writeShellApplication {
  name = "dns-resolver-helper";
  runtimeInputs = [
    bash
    coreutils
    killall
  ];
  text = builtins.readFile ../scripts/dns-resolver-helper;
}
