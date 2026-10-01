# writeShellApplication with bashOptions = [] preserves the script's own
# set-flags (or lack thereof) while still wrapping it with PATH from
# runtimeInputs.  This script is invoked by gpclient and depends on env
# variables that may be unset (CISCO_SPLIT_DNS, etc.) plus pipe patterns
# whose status codes get swallowed intentionally, both of which would
# break under the default errexit/nounset/pipefail.
#
# The script reads its JSON config path from $GP_AUTO_CONFIG, which is
# exported by gp-connect-auto (and inherited through gpclient) — see
# services.globalprotect-monitor in darwin-modules/global-protect-
# persistent.nix.
{
  bind,
  coreutils,
  dns-resolver-helper,
  gawk,
  gnugrep,
  gnused,
  jq,
  killall,
  nettools,
  writeShellApplication,
}:
writeShellApplication {
  name = "vpnc-script-macos";
  runtimeInputs = [
    # dig lives in the dnsutils output, not the default one.
    bind.dnsutils
    coreutils
    dns-resolver-helper
    gawk
    gnugrep
    gnused
    jq
    killall
    nettools
  ];
  bashOptions = [ ];
  text = builtins.readFile ../scripts/vpnc-script-macos;
}
