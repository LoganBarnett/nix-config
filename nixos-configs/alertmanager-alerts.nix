################################################################################
# Aggregates every subsystem's Prometheus alert rules.
#
# One file per subsystem, collected here, so that adding alerts for something
# new means writing a new file and adding a line below rather than growing
# nixos-configs/alertmanager.nix without bound.  That file stays about wiring
# up alertmanager itself.
#
# Subsystem files must contribute via services.prometheus.ruleFiles, not
# services.prometheus.rules.  The NixOS module joins every .rules entry into one
# file with concatStringsSep "\n", so two entries put two JSON documents in a
# single file and Prometheus quietly loads only one of them — promtool checks
# each document separately and passes, so nothing catches it until you notice
# alerts missing from /api/v1/rules.  Each .ruleFiles entry gets its own
# rule_files line instead.
#
# These belong on the Prometheus server.  The metrics they fire on are usually
# produced somewhere else entirely, so a subsystem's alert file and its metrics
# config are generally not imported by the same host.
################################################################################
{ ... }:
{
  imports = [
    ./goss-alertmanager-alerts.nix
    ./kodi-alertmanager-alerts.nix
    ./rtc-alertmanager-alerts.nix
    ./zwave-alertmanager-alerts.nix
  ];
}
