################################################################################
# Exports Z-Wave node health as Prometheus textfile metrics.
#
# The collector (zwave-metrics.js) takes one state dump per run from the
# zwave-js-server websocket that zwave-js-ui already exposes on localhost —
# the same interface OpenHAB consumes.  This is the driver's own view of the
# network, so it sees things no other host metric can: nodes the controller
# has marked Dead, battery levels, and Notification CC sensor states.
#
# Produced metrics:
#   zwave_node_dead
#       1 when the controller marks the node Dead.  Asleep battery devices are
#       healthy and do not count.  This is the alert that would have caught
#       the orphaned Long Range node 257, which sat dead for weeks after its
#       security keys were lost — see the history in zwave-js-ui.nix around
#       securityKeysLongRange.
#   zwave_node_battery_percent
#       Battery level per node, for devices that report it.  A water sensor
#       with a flat battery reports nothing at all, so low battery is itself
#       a monitoring failure in the making.
#   zwave_node_water_leak
#       1 when a node's Notification CC "Water Alarm" sensor status is
#       anything other than idle.
#   zwave_metrics_success
#       1 when the collection run succeeded, 0 when it could not reach or
#       read zwave-js-server.  Without this, a broken collector is
#       indistinguishable from a dry, healthy network.
#
# Alerts consuming these live in zwave-alertmanager-alerts.nix, collected by
# alertmanager-alerts.nix on the Prometheus host.  Metrics production belongs
# with zwave-js-ui and alert rules belong with the Prometheus server, so the
# files stay separate per that split even when one host wears both hats.
################################################################################
{
  lib,
  pkgs,
  ...
}:
let
  textfileDir = "/var/lib/zwave-metrics";
  outputPath = "${textfileDir}/zwave.prom";
in
{
  # The textfile directory is 0755 root:root; files written by this service
  # (running as root, umask 022) are 0644 root:root and thus readable by
  # node_exporter's unprivileged service user.
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ];

  # node_exporter's textfile directory flag is repeatable as of 1.5.0, so this
  # composes with other textfile producers on the same host (such as
  # dhcp-lease-textfile.nix) rather than fighting over a single flag.
  services.prometheus.exporters.node.extraFlags = [
    "--collector.textfile.directory=${textfileDir}"
  ];

  systemd.services.zwave-metrics = {
    description = "Generate Z-Wave node health Prometheus textfile metrics.";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.strings.concatStringsSep " " [
        "${pkgs.nodejs}/bin/node"
        "${./zwave-metrics.js}"
      ];
      Environment = [
        "OUTPUT_PATH=${outputPath}"
        "ZWAVE_WS_URL=ws://127.0.0.1:3004"
      ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ textfileDir ];
    };
  };

  systemd.timers.zwave-metrics = {
    description = "Periodically refresh Z-Wave node health Prometheus metrics.";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # A leak alert's end-to-end latency is this interval plus the scrape
      # interval plus rule evaluation, so 30s keeps detection comfortably
      # under a minute while remaining a trivial load: one localhost
      # websocket state dump per run.
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
    };
  };
}
