################################################################################
# Prometheus alert rules for Z-Wave network health.
#
# Collected by nixos-configs/alertmanager-alerts.nix.  The metrics these fire
# on are produced by nixos-configs/zwave-metrics.nix on the host running
# zwave-js-ui.
#
# Contributes a rule *file* via ruleFiles, not .rules — see the warning in
# kodi-alertmanager-alerts.nix for why that distinction is load-bearing.
################################################################################
{ facts, pkgs, ... }:
{
  services.prometheus.ruleFiles = [
    (pkgs.writeText "zwave-alerts.yml" (
      builtins.toJSON {
        groups = [
          {
            name = "zwave_alerts";
            rules = [
              {
                # Water where water should not be.  Fires immediately: the
                # sensor reports "dry" again the moment the probes clear
                # (parameter 2 defaults to 0 seconds of hold), so a firing
                # alert means the floor is wet right now.
                alert = "zwave_water_leak";
                expr = ''zwave_node_water_leak > 0'';
                "for" = "0m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{ $labels.label }} \"{{ $labels.name }}\" (node {{ $labels.node }}) detects water.";
                  description = ''
                    The water sensor's probes are bridged.  Go look at what it
                    is sitting under.  The alert resolves on its own once the
                    probes are dry.
                  '';
                };
              }
              {
                # A node the controller has given up on.  Asleep is normal for
                # battery devices and does not fire this; Dead means routed
                # frames go unanswered.  The orphaned Long Range node 257 sat
                # in exactly this state for weeks with nothing watching — this
                # alert exists so that never happens silently again.
                alert = "zwave_node_dead";
                expr = ''zwave_node_dead > 0'';
                "for" = "15m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Z-Wave node {{ $labels.node }} ({{ $labels.label }} \"{{ $labels.name }}\") is dead.";
                  description = ''
                    The controller marks this node Dead: it does not answer.
                    Dead batteries, orphaned security keys, and removed-but-not
                    -excluded hardware all land here.  Check the node at
                    https://zwave-js-ui.${facts.network.domain}.
                  '';
                };
              }
              {
                # A sensor with a flat battery stops reporting entirely, which
                # reads as "no leak" — low battery is a monitoring outage in
                # progress, not a convenience notification.
                alert = "zwave_node_battery_low";
                expr = ''zwave_node_battery_percent < 15'';
                "for" = "1h";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Z-Wave node {{ $labels.node }} ({{ $labels.label }} \"{{ $labels.name }}\") battery at {{ $value }}%.";
                  description = ''
                    Replace the battery soon.  A dead battery does not alert —
                    the device just goes quiet, and only zwave_node_dead or a
                    missed leak would reveal it.
                  '';
                };
              }
              {
                # The collector itself failed: zwave-js-server unreachable or
                # the state dump unreadable.  Everything above reads as
                # healthy while this fires, because absent metrics look
                # exactly like a dry network with charged batteries.  This is
                # the "is the smoke detector still plugged in" check.
                alert = "zwave_metrics_blind";
                expr = ''zwave_metrics_success == 0 or absent(zwave_metrics_success) == 1'';
                "for" = "10m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Z-Wave health metrics are blind.";
                  description = ''
                    The zwave-metrics collector cannot read zwave-js-server,
                    so no water leak, dead node, or battery alert can fire.
                    Check the zwave-metrics service on the host running
                    zwave-js-ui.
                  '';
                };
              }
              {
                # Companion guard to zwave_metrics_blind: catches the timer
                # dying while the last written file still says success.  The
                # textfile collector exports each file's mtime, so a frozen
                # file is visible even though its contents look healthy.
                alert = "zwave_metrics_stale";
                expr = ''time() - node_textfile_mtime_seconds{file=~".*zwave.prom"} > 300'';
                "for" = "10m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Z-Wave health metrics have not refreshed in 5 minutes.";
                  description = ''
                    The zwave-metrics timer on {{ $labels.instance }} has
                    stopped producing fresh output.  The metrics still being
                    served are frozen, so no Z-Wave alert can be trusted until
                    this is fixed.
                  '';
                };
              }
            ];
          }
        ];
      }
    ))
  ];
}
