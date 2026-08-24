################################################################################
# Prometheus alert rules for RTC (Real-Time Clock) battery health.  Typically
# this is held between unplugs (not just power off) by a dinky coin battery.
#
# Collected by nixos-configs/alertmanager-alerts.nix.  The rtc_battery_dead
# metric is produced at boot by nixos-configs/rtc-battery-textfile.nix, which
# compares the RTC against chrony's drift file before chronyd starts.
#
# Contributes a rule *file* via ruleFiles, not .rules — see the warning in
# alertmanager-alerts.nix for why that distinction is load-bearing.
#
# The latch lives in the metric, not in the rule: the textfile value holds
# for the entire uptime (the producer refuses to overwrite the boot verdict
# once chronyd has run), so the alert keeps firing after the clock itself has
# recovered and clears only when a later boot starts with a sane RTC.  That
# persistence is the point — during the incident itself the alerting path is
# down along with everything else, so the alert's job is to be waiting once
# the network heals.
################################################################################
{ pkgs, ... }:
let
  ruleFile =
    type: root: pkgs.writeText "${type}-alerts.yaml" (builtins.toJSON root);
in
{
  services.prometheus.ruleFiles = [
    (ruleFile "rtc" {
      groups = [
        {
          name = "rtc_alerts";
          rules = [
            {
              # The metric is steady for the whole uptime, so the hold only
              # needs to ride out scrape flaps.
              alert = "rtc_battery_dead";
              expr = "rtc_battery_dead == 1";
              "for" = "5m";
              labels = {
                severity = "warning";
              };
              annotations = {
                summary = ''
                  {{ $labels.instance }}: the RTC battery is dead — replace it.
                '';
                description = ''
                  The RTC on {{ $labels.instance }} lost state across the last
                  power cut, so its battery is dead and boot-time security is
                  minorly degraded: each dead-battery boot starts years in the
                  past and must trust unauthenticated NTP for a large clock
                  step before certificate and DNSSEC validation mean anything.
                  Replace the CMOS battery.  This alert latches for the whole
                  uptime and clears only after a boot whose RTC reads sane —
                  note that an ordinary mains-powered reboot also clears it,
                  because the RTC runs on standby power; the battery's true
                  state is only observable across a full power cut.
                '';
              };
            }
          ];
        }
      ];
    })
  ];
}
