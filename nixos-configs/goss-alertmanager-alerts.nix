################################################################################
# Prometheus alert rules for goss health checks.
#
# Collected by nixos-configs/alertmanager-alerts.nix.  The metrics these fire
# on are produced by every host that declares "goss" in networking.monitors;
# nixos-modules/prometheus-server.nix scrapes /healthz on port 8080.
#
# Contributes a rule *file* via ruleFiles, not .rules — see the warning in
# alertmanager-alerts.nix for why that distinction is load-bearing.
#
# goss exports exactly three labels: outcome, resource_id, and type.  There is
# no resource_type label, and type values are lower case ("mount", not
# "Mount").  A selector naming a label goss does not emit matches no series and
# the rule silently never fires, which is indistinguishable from a healthy
# system.  Verify new selectors against a live /healthz before trusting them.
#
# goss_tests_outcomes_total is a counter over the goss process lifetime, so a
# bare "> 0" latches forever after the first failure and can never resolve.
# Every rule here wraps it in increase() over a window to recover current
# state.
################################################################################
{ facts, pkgs, ... }:
let
  ruleFile =
    type: root: pkgs.writeText "${type}-alerts.yaml" (builtins.toJSON root);
in
{
  services.prometheus.ruleFiles = [
    (ruleFile "goss" {
      groups = [
        {
          name = "goss_alerts";
          rules = [
            {
              # The catch-all: any goss check that stays red gets noticed.
              # Every check a host declares is covered the moment it is written,
              # with no per-check alert rule to remember.
              #
              # The 10m window paired with a 15m hold suppresses deploy churn.
              # A service restarting during activation fails one or two scrapes,
              # which keeps increase() positive for at most ten minutes — short
              # of the fifteen minutes the alert must hold before firing.  A
              # genuinely broken check keeps the window populated indefinitely
              # and fires.
              #
              # tls-cert-expiry-* and /nix/store are excluded because each has a
              # dedicated rule below with different urgency; without the
              # exclusions a single failure would notify twice.
              alert = "goss_check_failing";
              expr = ''
                increase(
                  goss_tests_outcomes_total{
                    outcome="fail",
                    resource_id!~"tls-cert-expiry-.*",
                    resource_id!="/nix/store"
                  }[10m]
                ) > 0
              '';
              "for" = "15m";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = "{{ $labels.instance }}: goss check {{ $labels.resource_id }} ({{ $labels.type }}) is failing.";
                description = ''
                  The {{ $labels.type }} check for {{ $labels.resource_id }} on
                  {{ $labels.instance }} has been failing for more than fifteen
                  minutes, so this is not deploy churn.  Read the full check
                  output at http://{{ $labels.instance }}:8080/healthz.
                '';
              };
            }
            {
              # An internal leaf certificate inside its expiry warning window,
              # per the goss check in nixos-modules/tls-leaf.nix (30 days by
              # default, tls.expiry-warning-days).
              #
              # Leaf certs are store paths baked into the consuming service's
              # config, so renewal is a two-step affair: regenerate and commit
              # the cert, then deploy every host that serves it.  A cert fixed
              # in git is still expired on any host running an older generation.
              # This alert only clears once the new cert is actually deployed,
              # which is the property that matters.
              #
              # A 30m hold rather than 15m because a 30-day fuse has no urgency
              # whatsoever, and riding out deploys entirely is worth more than
              # firing sooner.
              alert = "tls_certificate_expiring";
              expr = ''
                increase(
                  goss_tests_outcomes_total{
                    outcome="fail",
                    resource_id=~"tls-cert-expiry-.*"
                  }[10m]
                ) > 0
              '';
              "for" = "30m";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = "{{ $labels.instance }}: certificate for {{ $labels.resource_id }} is near or past expiry.";
                description = ''
                  Regenerate the leaf with agenix, commit the new cert, and then
                  deploy every host that serves it.  Committing alone does not
                  resolve this alert — the old cert stays on the wire until the
                  host picks up a generation carrying the new store path.
                '';
              };
            }
            {
              # The smoke-detector-still-plugged-in check.  Every rule above
              # reads as healthy when goss stops being scraped, because a check
              # that reports nothing looks exactly like a check that passes.
              # Without this, losing goss silently disarms all of it.
              alert = "goss_blind";
              expr = ''up{job="goss"} == 0'';
              "for" = "10m";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = "{{ $labels.instance }}: goss checks are not being scraped.";
                description = ''
                  Prometheus cannot reach the goss exporter on {{
                  $labels.instance }}, so no goss-backed alert can fire for that
                  host — including certificate expiry.  Check the goss service
                  and that port 8080 is reachable from
                  prometheus.${facts.network.domain}.
                '';
              };
            }
          ];
        }
      ];
    })
  ];
}
