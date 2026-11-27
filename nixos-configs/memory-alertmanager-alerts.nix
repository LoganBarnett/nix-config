################################################################################
# Prometheus alert rules for host memory.
#
# Collected by nixos-configs/alertmanager-alerts.nix.  Contributes a rule file
# via ruleFiles, not .rules.  See the warning there for why.
#
# A host that runs out of memory with no disk swap does not crash.  It
# livelocks.  The kernel keeps answering pings while no userspace runs and every
# exporter goes dark, so node_down is the first signal and it arrives after the
# host is already gone.  Bromine did this on 2026-11-24 after 32 days of a slow
# chromium leak.  This rule fires days before that point.  The runbook is
# docs/operations/memory-livelock.org.
#
# The expression is the one the Memory Usage panel in
# nixos-configs/grafana-host-monitor.nix draws, so the alert and the graph
# agree.  Linux hosts emit MemAvailable.  Darwin hosts do not, so free plus
# inactive plus purgeable stands in.  Each host emits one form and the or unions
# them.  The comparison sits outside the union because PromQL binds a comparison
# tighter than or.
################################################################################
{ pkgs, ... }:
let
  ruleFile =
    type: root: pkgs.writeText "${type}-alerts.yaml" (builtins.toJSON root);
in
{
  services.prometheus.ruleFiles = [
    (ruleFile "memory" {
      groups = [
        {
          name = "memory_alerts";
          rules = [
            {
              # Two hours rides out a build or a backup and still leaves days of
              # warning against a leak of tens of megabytes a day.  Both numbers
              # are round, not measured.
              alert = "host_memory_high";
              expr = ''
                (
                  (
                    1 - node_memory_MemAvailable_bytes
                      / node_memory_MemTotal_bytes
                  ) * 100
                  or
                  (
                    1 - (
                      node_memory_free_bytes
                      + node_memory_inactive_bytes
                      + node_memory_purgeable_bytes
                    ) / node_memory_total_bytes
                  ) * 100
                ) > 90
              '';
              "for" = "2h";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = ''
                  {{ $labels.host }}: memory {{ $value | printf "%.0f" }}% used.
                '';
                description = ''
                  {{ $labels.host }} has used more than 90% of its memory for
                  two hours.  A host with no disk swap livelocks when memory
                  runs out, so find what is growing before it gets there.  See
                  docs/operations/memory-livelock.org.
                '';
              };
            }
          ];
        }
      ];
    })
  ];
}
