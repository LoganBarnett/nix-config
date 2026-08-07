################################################################################
# Exports Kodi audio engine health as Prometheus textfile metrics.
#
# Kodi's audio engine (CActiveAE) can deadlock in a way that leaves the rest of
# the process looking perfectly healthy: the systemd unit is active, the
# JSON-RPC API answers, video plays, PipeWire still advertises the HDMI sink
# unmuted at full volume.  Only the audio is gone, and it stays gone until Kodi
# is restarted.  Nothing in node or systemd metrics can see that, so this
# config scrapes the signatures out of Kodi's own log instead.
#
# Produced metrics:
#   kodi_audio_display_loss_timeouts_total
#       CActiveAE failed to acknowledge an OnLostDisplay teardown within its
#       five second deadline.  This is the leading indicator: it began roughly
#       two days before audio actually died in the failure this was written
#       for, which is the whole reason it is worth alerting on.
#   kodi_audio_renderer_failures_total
#       CActiveAE could not create a stream for a decoded track.  This is the
#       terminal signature — audio is dead right now.
#   kodi_audio_xrandr_query_failures_total
#       CXRandR::Query returned no connected output with a current mode, i.e.
#       the display link dropped out from under Kodi.  This is the upstream
#       cause rather than a fault in itself; it is exported to tell "the TV
#       stopped flapping" apart from "the TV still flaps but Kodi now copes",
#       which is exactly the question the connector pinning in
#       hosts/krypton.nix is meant to answer.
#   kodi_audio_log_present
#       1 when Kodi's log was readable, 0 otherwise.  Without this, a missing
#       or renamed log is indistinguishable from a perfectly healthy Kodi,
#       since both report zero for everything above.
#
# All three counters reset to zero whenever Kodi restarts, because Kodi rotates
# its log on startup.  That is fine and in fact wanted: the alerts use
# increase() over a window, which handles counter resets, and a restart is
# genuinely the point where the wedge is cleared.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.kodi-standalone;
  textfileDir = "/var/lib/kodi-audio-health";
  kodiLog = "/home/${cfg.systemUser}/.kodi/temp/kodi.log";

  audioHealthScript = pkgs.writeShellScript "kodi-audio-health-metrics" ''
    set -euo pipefail

    DIR="${textfileDir}"
    TMP_OUTPUT="''${DIR}/kodi-audio-health.prom.tmp"
    OUTPUT="''${DIR}/kodi-audio-health.prom"
    LOG="${kodiLog}"

    # grep exits 1 when it matches nothing, which is a normal and expected
    # result here — a healthy Kodi matches none of these.  Under `set -e` that
    # would abort the script, so each count absorbs the non-match exit.
    count_matches() {
      if [[ -r "''${LOG}" ]]; then
        ${pkgs.gnugrep}/bin/grep \
          --count \
          --fixed-strings \
          -- "$1" \
          "''${LOG}" \
          || true
      else
        echo 0
      fi
    }

    if [[ -r "''${LOG}" ]]; then
      log_present=1
    else
      log_present=0
    fi

    timeouts=$(count_matches 'ActiveAE::OnLostDisplay - timed out')
    renderer_failures=$(count_matches 'failed to create audio renderer')
    xrandr_failures=$(count_matches 'RefreshWindow - failed to query xrandr')

    # Deliberately not a heredoc.  Prometheus rejects lines with leading
    # whitespace, and a heredoc body's indentation inside a Nix indented
    # string is at the mercy of the formatter — nixfmt reindents this literal,
    # and the terminator then has to happen to land back at column zero once
    # Nix strips the common indent.  printf does not care how this file is
    # formatted.
    ${pkgs.coreutils}/bin/printf '%s\n' \
      '# HELP kodi_audio_display_loss_timeouts_total CActiveAE missed its OnLostDisplay teardown deadline.' \
      '# TYPE kodi_audio_display_loss_timeouts_total counter' \
      "kodi_audio_display_loss_timeouts_total ''${timeouts}" \
      '# HELP kodi_audio_renderer_failures_total CActiveAE could not create an audio stream; audio is dead.' \
      '# TYPE kodi_audio_renderer_failures_total counter' \
      "kodi_audio_renderer_failures_total ''${renderer_failures}" \
      '# HELP kodi_audio_xrandr_query_failures_total Kodi found no connected output with a current mode.' \
      '# TYPE kodi_audio_xrandr_query_failures_total counter' \
      "kodi_audio_xrandr_query_failures_total ''${xrandr_failures}" \
      "# HELP kodi_audio_log_present Whether Kodi's log file was readable when metrics were generated." \
      '# TYPE kodi_audio_log_present gauge' \
      "kodi_audio_log_present ''${log_present}" \
      > "''${TMP_OUTPUT}"

    # Atomic replacement prevents node_exporter from reading a partial file.
    ${pkgs.coreutils}/bin/mv "''${TMP_OUTPUT}" "''${OUTPUT}"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # The textfile directory is 0755 root:root; files written by this service
    # (running as root, umask 022) are 0644 root:root and thus readable by
    # node_exporter's unprivileged service user.
    systemd.tmpfiles.rules = [
      "d ${textfileDir} 0755 root root -"
    ];

    # node_exporter's textfile directory flag is repeatable as of 1.5.0, so
    # multiple producers on one host may each contribute their own directory
    # via extraFlags (dhcp-lease-textfile.nix and zwave-metrics.nix coexist
    # this way).  An earlier version of this comment prescribed a
    # shared-module refactor under the belief the flag was single-occupancy;
    # that is no longer true.
    services.prometheus.exporters.node.extraFlags = [
      "--collector.textfile.directory=${textfileDir}"
    ];

    systemd.services.kodi-audio-health-metrics = {
      description = "Generate Kodi audio health Prometheus textfile metrics.";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${audioHealthScript}";
        # Restrict filesystem access to only what the script requires.  Note
        # ProtectHome is "read-only" rather than true: Kodi's log lives under
        # the Kodi user's home, so blocking /home entirely would make every
        # metric read zero and the fault would look like health.
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ textfileDir ];
      };
    };

    systemd.timers.kodi-audio-health-metrics = {
      description = "Periodically refresh Kodi audio health Prometheus metrics.";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # The failure this watches for develops over days, so there is nothing
        # to gain from a tight interval.  Once a minute keeps the alert's
        # increase() windows well populated at the 10s scrape interval.
        OnBootSec = "1m";
        OnUnitActiveSec = "1m";
      };
    };
  };
}
