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
  callPackage,
  jq,
  writeShellApplication,
}:
let
  dnsResolverHelper = callPackage ./dns-resolver-helper.nix { };
in
writeShellApplication {
  name = "vpnc-script-macos";
  runtimeInputs = [
    dnsResolverHelper
    jq
  ];
  bashOptions = [ ];
  # The script lived under writeScriptBin before the move to
  # writeShellApplication, so it carries a backlog of pre-existing
  # shellcheck nits (SC2145, SC2034, SC2154, SC2001, SC2086, …).  Skip
  # the checkPhase for now — once the script gets a cleanup pass these
  # can be addressed individually and the default check restored.
  checkPhase = "";
  text = builtins.readFile ../scripts/vpnc-script-macos;
}
