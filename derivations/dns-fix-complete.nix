{
  bash,
  coreutils,
  jq,
  writeShellApplication,
  ...
}:

# Manual repair script for when DNS scoping gets wedged on macOS.  Reads
# its corporate-domain regex and local DNS server from the JSON file
# whose path is supplied via the GP_AUTO_CONFIG env var (default value
# set by services.globalprotect-monitor — see configFile / environment.
# variables — and overridable at invocation time).
writeShellApplication {
  name = "dns-fix-complete";
  runtimeInputs = [
    bash
    coreutils
    jq
  ];
  text = builtins.readFile ../scripts/dns-fix-complete;
}
