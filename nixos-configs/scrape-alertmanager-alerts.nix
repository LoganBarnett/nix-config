################################################################################
# Prometheus alert rules for the scrape layer itself.
#
# Every other rule in this repository reads as healthy when its exporter stops
# being scraped, because a metric that is not there looks exactly like a metric
# that is fine.  These two rules make the scrape layer fail loudly instead.
#
# Both key on the host label that nixos-modules/prometheus-server.nix stamps
# on every static target, and on the scrape_target_expected series it records
# for every host and job pair facts says should exist.
#
# Collected by nixos-configs/alertmanager-alerts.nix.  Contributes a rule file
# via ruleFiles, not .rules.  See the warning there for why.
################################################################################
{ pkgs, ... }:
let
  ruleFile =
    type: root: pkgs.writeText "${type}-alerts.yaml" (builtins.toJSON root);
in
{
  services.prometheus.ruleFiles = [
    (ruleFile "scrape" {
      groups = [
        {
          name = "scrape_alerts";
          rules = [
            {
              # A live host with a dead exporter.  node_down already covers a
              # host that is gone entirely, and the unless clause keeps a dead
              # host from paging once per exporter on top of that.
              alert = "exporter_down";
              expr = ''
                up == 0
                unless on (host) (up{job="node"} == 0)
              '';
              "for" = "10m";
              labels = {
                severity = "page";
              };
              annotations = {
                summary = ''
                  {{ $labels.host }}: the {{ $labels.job }} exporter is dark.
                '';
                description = ''
                  Prometheus cannot scrape {{ $labels.job }} on {{ $labels.host
                  }} while the host itself answers.  Every rule and panel fed by
                  that exporter now reads as healthy with nothing behind it.
                  Check the service on the host, and that {{ $labels.instance }}
                  is reachable from prometheus.proton.
                '';
              };
            }
            {
              # A target facts expects that Prometheus is not scraping at all.
              # There is no up series to be zero, so only the expected series
              # can see it.  Declared monitors that are missing point at a
              # config that did not load.  Required monitors that are missing
              # point at a host whose networking.monitors forgot one.
              alert = "scrape_target_missing";
              expr = ''
                scrape_target_expected
                unless on (host, job) up
              '';
              "for" = "15m";
              labels = {
                severity = "page";
              };
              annotations = {
                summary = ''
                  {{ $labels.host }}: {{ $labels.job }} is not in the scrape set.
                '';
                description = ''
                  facts expects Prometheus to scrape {{ $labels.job }} on {{
                  $labels.host }}, but no up series exists for it, so no rule
                  keyed on up can fire for that exporter.  The target list is
                  generated in nixos-modules/prometheus-server.nix from the
                  host's networking.monitors and its facts entry.
                '';
              };
            }
          ];
        }
      ];
    })
  ];
}
