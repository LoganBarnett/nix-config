################################################################################
# Detects a dead RTC (Real-Time Clock) battery at boot and exports the verdict
# as Prometheus textfile metrics.  RTC batteries are typically held aloft by a
# dinky coin battery, and their values are lost when unplugged (not just
# power-downs).
#
# The mechanism relies on an invariant of a healthy powered-off machine: the
# RTC keeps counting while chrony's drift file modification time stays frozen
# at the last write before shutdown, so at boot the RTC always reads later
# than the drift file.  An RTC reading *earlier* than the drift file means it
# lost state across the power cut — the battery is dead.  A real failure
# manifests as years (silicon's RTC reset to 2013), so the one-day margin
# below is comfortably clear of ordinary drift.
#
# The reading is only meaningful before chronyd runs: chronyd's rtcautotrim
# corrects the RTC shortly after the first sync, and chronyd rewrites the
# drift file hourly, destroying both halves of the comparison.  The unit is
# therefore ordered before chronyd.service, and the script refuses to
# overwrite the boot verdict once chronyd has run this boot (see the guard
# below).  That refusal is what makes the alert latch: the metric holds for
# the whole uptime and clears only when a subsequent boot passes the check.
#
# Known limitation: an ordinary mains-powered reboot keeps the RTC alive on
# standby power, so it clears the alert even if the battery is still dead.
# The battery's true state is only observable across a full power cut.
#
# Produced metrics:
#   rtc_present             - Whether the host has a hardware RTC at all.
#                             Raspberry Pis have none and are never flagged.
#   rtc_battery_dead        - Whether the boot-time RTC read implausibly
#                             earlier than the drift file.
#   rtc_boot_offset_seconds - Drift file mtime minus RTC time at boot.
#                             Healthy boots are negative.
#
# The alert on rtc_battery_dead lives in
# nixos-configs/rtc-alertmanager-alerts.nix.
################################################################################
{ pkgs, ... }:
let
  textfileDir = "/var/lib/rtc-battery-exporter";

  rtcBatteryMetricsScript = pkgs.writeShellScript "rtc-battery-metrics" ''
    set -euo pipefail

    RTC_SYSFS="/sys/class/rtc/rtc0/since_epoch"
    DRIFT_FILE="/var/lib/chrony/chrony.drift"
    DIR="${textfileDir}"
    TMP_OUTPUT="''${DIR}/rtc-battery.prom.tmp"
    OUTPUT="''${DIR}/rtc-battery.prom"

    # chronyd creates /run/chrony for its command socket, and /run is a
    # per-boot tmpfs, so this tests "has chronyd run at all this boot".  A
    # rerun after that point (a deploy restarting a changed unit, a manual
    # start) would read a freshly trimmed RTC and always conclude "healthy",
    # falsely clearing the latched alert — so keep the boot verdict instead.
    if [[ -e /run/chrony ]]; then
      exit 0
    fi

    rtc_present=0
    rtc_battery_dead=0
    rtc_boot_offset_seconds=0

    # See the header comment for the invariant this margin sits against.
    margin_seconds=86400

    if [[ -r "''${RTC_SYSFS}" ]]; then
      rtc_present=1
      rtc_seconds=$(${pkgs.coreutils}/bin/cat "''${RTC_SYSFS}")
      # A missing drift file means chrony has never synchronized (first boot
      # of a fresh install); there is no reference to compare against, so
      # report healthy rather than guess.
      if [[ -f "''${DRIFT_FILE}" ]]; then
        drift_mtime=$(${pkgs.coreutils}/bin/stat --format=%Y "''${DRIFT_FILE}")
        rtc_boot_offset_seconds=$(( drift_mtime - rtc_seconds ))
        if (( rtc_boot_offset_seconds > margin_seconds )); then
          rtc_battery_dead=1
        fi
      fi
    fi

    ${pkgs.coreutils}/bin/cat > "''${TMP_OUTPUT}" << PROM
    # HELP rtc_present Whether this host has a hardware RTC.
    # TYPE rtc_present gauge
    rtc_present ''${rtc_present}
    # HELP rtc_battery_dead Whether the RTC read implausibly earlier than chrony's drift file at boot, meaning the battery failed across a power cut.  Latched for the whole uptime.
    # TYPE rtc_battery_dead gauge
    rtc_battery_dead ''${rtc_battery_dead}
    # HELP rtc_boot_offset_seconds Drift file mtime minus RTC time, measured at boot before chronyd started.  Healthy boots are negative.
    # TYPE rtc_boot_offset_seconds gauge
    rtc_boot_offset_seconds ''${rtc_boot_offset_seconds}
    PROM

    # Atomic replacement prevents node_exporter from reading a partial file.
    ${pkgs.coreutils}/bin/mv "''${TMP_OUTPUT}" "''${OUTPUT}"
  '';
in
{
  # The textfile directory is 0755 root:root; files written by this service
  # (running as root, umask 022) are 0644 root:root and thus readable by
  # node_exporter's unprivileged service user.
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ];

  # node_exporter's textfile directory flag is repeatable, so this composes
  # with other textfile modules (e.g. dhcp-lease-textfile.nix) that each
  # declare their own directory.
  services.prometheus.exporters.node.extraFlags = [
    "--collector.textfile.directory=${textfileDir}"
  ];

  systemd.services.rtc-battery-metrics = {
    description = ''
      Record the boot-time RTC battery verdict as Prometheus textfile metrics.
    '';
    # The comparison is only valid before chronyd touches the RTC and the
    # drift file — see the header comment.
    before = [ "chronyd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      # Stay "active" after running so activation of an unchanged system does
      # not restart the unit on every deploy.  The /run/chrony guard in the
      # script covers the cases that do rerun it.
      RemainAfterExit = true;
      ExecStart = "${rtcBatteryMetricsScript}";
      # Restrict filesystem access to only what the script requires.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadOnlyPaths = [ "/var/lib/chrony" ];
      ReadWritePaths = [ textfileDir ];
    };
  };
}
