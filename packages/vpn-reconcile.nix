################################################################################
# vpn-reconcile — packaged reconciler that keeps the WireGuard tunnel in the
# right state as the laptop roams.  Driven by the sytter sytts in
# ../darwin-configs/sytter.nix (a 60s cron tick plus Wake / network-device
# events).  See ./vpn-reconcile.sh for the behavior.
#
# Home detection reads the MAC(s) of whichever host facts designates as the
# network gateway (network.gateway-host), so there is a single source of truth
# and nothing is duplicated here.
################################################################################
{
  facts,
  lib,
  wireguard-tools,
  wireguard-go,
  gawk,
  writeShellApplication,
  ...
}:
let
  # Space-separated, already lowercased by the helper.
  homeGatewayMacs = lib.concatStringsSep " " (
    lib.custom.networkGatewayMacs facts
  );
  homeSubnetPrefix = facts.network.subnets.barnett-main;
  # The wg-quick interface names declared in
  # ../nixos-configs/wireguard/client-standard.nix.
  splitIface = "proton";
  fullIface = "proton-only";
  # silicon's in-tunnel address (server IP of the 192.168.102.0/24 VPN subnet).
  tunnelProbeIp = "192.168.102.1";
  stateDir = "/var/lib/vpn-reconcile";
  # Consider the tunnel dead if no handshake within this many seconds and the
  # in-tunnel probe also fails.
  handshakeMaxAge = 180;
in
writeShellApplication {
  name = "vpn-reconcile";
  runtimeInputs = [
    wireguard-tools # wg, wg-quick
    wireguard-go # wg-quick's userspace backend on darwin
    gawk # `awk` with strtonum for MAC normalization
  ];
  text = ''
    HOME_GATEWAY_MACS=${lib.escapeShellArg homeGatewayMacs}
    HOME_SUBNET_PREFIX=${lib.escapeShellArg homeSubnetPrefix}
    SPLIT_IFACE=${lib.escapeShellArg splitIface}
    FULL_IFACE=${lib.escapeShellArg fullIface}
    TUNNEL_PROBE_IP=${lib.escapeShellArg tunnelProbeIp}
    STATE_DIR=${lib.escapeShellArg stateDir}
    HANDSHAKE_MAX_AGE=${toString handshakeMaxAge}
  ''
  + builtins.readFile ./vpn-reconcile.sh;
}
