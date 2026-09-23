################################################################################
# Enables the Prometheus node exporter (nix-darwin's built-in module) on
# darwin hosts that declare "node" in networking.monitors.  Roaming hosts
# skip it: prometheus-server.nix never scrapes them, so the listener would
# only expose metrics on untrusted networks.
################################################################################
{
  config,
  facts,
  host-id,
  lib,
  ...
}:
let
  node-enabled =
    builtins.elem "node" config.networking.monitors
    && !(facts.network.hosts.${host-id}.roaming or false);
  exporter = config.services.prometheus.exporters.node;
  exporter-user = config.users.users._prometheus-node-exporter;
in
{
  services.prometheus.exporters.node.enable = node-enabled;

  # macOS records the exporter user's home with /var resolved to /private/var,
  # and nix-darwin's activation aborts when its declared home differs from that
  # record, so declare the canonical path instead of the module's /var form.
  # The module defines the home at the default priority (100), so a plain
  # definition here would conflict with it; 90 outranks it while leaving
  # mkForce available to any host that needs to override this in turn.
  users.users = lib.mkIf node-enabled {
    _prometheus-node-exporter.home = lib.mkOverride 90 "/private/var/lib/prometheus-node-exporter";
  };

  # nix-darwin's module logs into the exporter user's home, which the
  # rotation machinery can only touch when told to drop to that identity.
  services.log-rotation.files = lib.mkIf node-enabled {
    prometheus-node-exporter = {
      path = "${exporter-user.home}/prometheus-node-exporter.log";
      user = "_prometheus-node-exporter";
      group = "_prometheus-node-exporter";
    };
  };

  # Register with the macOS Application Firewall so the Prometheus server can
  # scrape over the LAN if the firewall is ever enabled.  The binary path is
  # re-registered on every activation because it changes when the derivation
  # is updated.
  system.activationScripts.postActivation.text = lib.mkIf node-enabled ''
    /usr/libexec/ApplicationFirewall/socketfilterfw \
      --add ${lib.getExe exporter.package} >/dev/null 2>&1 || true
    /usr/libexec/ApplicationFirewall/socketfilterfw \
      --unblockapp ${lib.getExe exporter.package} >/dev/null 2>&1 || true
  '';
}
