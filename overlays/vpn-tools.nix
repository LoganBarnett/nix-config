################################################################################
# The GlobalProtect and split-DNS tool set as first-class pkgs attributes.
#
# Every consumer (systemPackages, a sudoers rule, another tool's
# runtimeInputs) refers to the same attribute, so a NOPASSWD rule and the
# script that invokes the tool agree on the store path by construction.  A
# variant is an explicit `.override`, never a second callPackage.
################################################################################
final: prev: {
  cleanup-vpn = final.callPackage ../derivations/cleanup-vpn.nix { };
  dns-fix-complete = final.callPackage ../derivations/dns-fix-complete.nix { };
  dns-resolver-helper =
    final.callPackage ../derivations/dns-resolver-helper.nix
      { };
  dns-vpn-scoping-fix =
    final.callPackage ../derivations/dns-vpn-scoping-fix.nix
      { };
  dnsflush = final.callPackage ../derivations/dnsflush.nix { };
  dnsmasq-upstream-sync =
    final.callPackage ../derivations/dnsmasq-upstream-sync/default.nix
      { };
  gp-connect = final.callPackage ../derivations/gp-connect.nix { };
  gp-connect-auto = final.callPackage ../derivations/gp-connect-auto.nix { };
  gp-monitor = final.callPackage ../derivations/gp-monitor.nix { };
  test-vpn-connectivity =
    final.callPackage ../derivations/test-vpn-connectivity.nix
      { };
  vpn-dns-recover = final.callPackage ../derivations/vpn-dns-recover.nix { };
  vpn-test-harness = final.callPackage ../derivations/vpn-test-harness.nix { };
  vpn-test-harness-recover =
    final.callPackage ../derivations/vpn-test-harness-recover.nix
      { };
  vpnc-script-macos = final.callPackage ../derivations/vpnc-script-macos.nix { };
}
