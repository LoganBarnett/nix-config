################################################################################
# DNS/DHCP Server Integration Module.
#
# This module integrates Blocky (DNS ad-blocking/classification) with dnsmasq
# (DHCP + local hostname resolution) to provide a complete DNS/DHCP solution.
#
# Architecture:
# - Blocky (port 53): Primary DNS for all clients with ad-blocking
# - dnsmasq (own port, set in dhcp-server.nix): Local hostname resolution for
#   the .proton domain and its reverse zone
# - dnsmasq (port 67): DHCP server
#
# This module handles:
# - Importing and configuring both services
# - Ensuring proper startup order (dnsmasq before blocky)
# - Integration testing via goss to verify the services work together
################################################################################
{
  config,
  host-id,
  facts,
  pkgs,
  ...
}:
{
  imports = [
    ../nixos-configs/blocky-with-updater.nix
    ./dhcp-server.nix
  ];

  # Blocky, dnsmasq, and unbound are all expected to run on the same host, so we
  # need to make sure we don't get port conflicts.
  assertions =
    let
      dnsmasq-port = toString config.services.dnsmasq.settings.port;
    in
    [
      {
        assertion =
          dnsmasq-port != (toString config.services.blocky.settings.ports.dns);
        message =
          "dnsmasq and blocky both listen on DNS port ${dnsmasq-port}."
          + "  Set services.dnsmasq.settings.port to a free port.";
      }
      {
        assertion =
          !config.services.unbound.enable
          ||
            dnsmasq-port
            != (toString config.services.unbound.settings.server.port);
        message =
          "dnsmasq and unbound both listen on DNS port ${dnsmasq-port}."
          + "  Set services.dnsmasq.settings.port to a free port.";
      }
    ];

  # Ensure blocky starts after dnsmasq since it queries dnsmasq for local
  # hostname resolution.
  systemd.services.blocky = {
    after = [ "dnsmasq.service" ];
    wants = [ "dnsmasq.service" ];
  };

  # Verify blocky and dnsmasq work together.
  services.goss.checks.dns =
    let
      via-blocky = {
        resolvable = true;
        server = "127.0.0.1";
        timeout = 3000;
      };
      subnet = facts.network.subnets.barnett-main;
      my-ip = "${subnet}.${toString facts.network.hosts.${host-id}.ipv4}";
    in
    {
      "${host-id}.${facts.network.domain}" = via-blocky;
      # The reverse zone needs its own conditional mapping in blocky.  Without
      # it blocky answers NXDOMAIN before dnsmasq is ever asked.  goss reads the
      # record type from the prefix.
      "PTR:${pkgs.lib.custom.inAddrArpa my-ip}" = via-blocky;
    };
}
