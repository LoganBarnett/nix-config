################################################################################
# Aggregates every subsystem's Prometheus alert rules.
#
# One file per subsystem, collected here, so that adding alerts for something
# new means writing a new file and adding a line below rather than growing
# nixos-configs/alertmanager.nix without bound.  That file stays about wiring
# up alertmanager itself.
#
# services.prometheus.rules is a list and Prometheus loads several rule files
# happily, so each subsystem appends its own group instead of editing a shared
# one.
#
# These belong on the Prometheus server.  The metrics they fire on are usually
# produced somewhere else entirely, so a subsystem's alert file and its metrics
# config are generally not imported by the same host.
################################################################################
{ ... }:
{
  imports = [
    ./kodi-alertmanager-alerts.nix
  ];
}
