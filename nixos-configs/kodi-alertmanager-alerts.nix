################################################################################
# Prometheus alert rules for Kodi audio engine health.
#
# Collected by nixos-configs/alertmanager-alerts.nix.  The metrics these fire
# on are produced by nixos-configs/kodi-audio-health.nix over on the Kodi host.
# See docs/kodi-audio-engine-wedge.org for the failure mode they exist to
# catch.
#
# This contributes a rule *file* rather than adding to services.prometheus.rules.
# That distinction is load-bearing: the NixOS module concatenates every entry of
# .rules into a single file with concatStringsSep "\n", so a second entry lands
# a second JSON document in the same file and Prometheus silently keeps only one
# of them.  Doing that dropped node_alerts and ollama_alerts on silicon once
# already.  .ruleFiles entries each become their own rule_files line, which is
# what makes per-subsystem files work at all.
################################################################################
{ pkgs, ... }:
{
  services.prometheus.ruleFiles = [
    (pkgs.writeText "kodi-alerts.yml" (
      builtins.toJSON {
        groups = [
          {
            name = "kodi_alerts";
            rules = [
              {
                # The leading indicator.  CActiveAE has started missing its
                # OnLostDisplay teardown deadline, which historically ran for
                # about two days before the audio engine deadlocked outright.
                # Nothing is broken for the viewer yet, so this is deliberately
                # not a page — it is the window in which a restart is cheap and
                # can be taken at a civilised hour.
                #
                # A one hour window rather than five minutes because the
                # underlying display flap is itself roughly hourly; a shorter
                # window would sit at zero between flaps and flap the alert along
                # with it.
                alert = "kodi_audio_engine_degraded";
                expr = ''increase(kodi_audio_display_loss_timeouts_total[1h]) > 0'';
                for = "10m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "{{ $labels.instance }}: Kodi audio engine is degrading.";
                  description = ''
                    CActiveAE on {{ $labels.instance }} is failing to acknowledge
                    display-loss teardowns within its deadline.  Audio still
                    works, but this is how the engine deadlocks: left alone it
                    ends with video playing and no sound at all.  Restart
                    kodi.service on the host to clear it.  See
                    docs/kodi-audio-engine-wedge.org.
                  '';
                };
              }
              {
                # The terminal signature.  Kodi could not build an audio renderer
                # for a track it is decoding, which means someone is sitting in
                # front of a silent film right now.  Fires fast and pages.
                alert = "kodi_audio_engine_wedged";
                expr = ''increase(kodi_audio_renderer_failures_total[10m]) > 0'';
                for = "0m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{ $labels.instance }}: Kodi has no audio.";
                  description = ''
                    CActiveAE on {{ $labels.instance }} is failing to create audio
                    streams.  Playback continues with no sound; PipeWire and the
                    HDMI sink will look entirely healthy, because the fault is
                    inside Kodi.  Restart kodi.service on the host.  See
                    docs/kodi-audio-engine-wedge.org.
                  '';
                };
              }
              {
                # Guards the two alerts above.  Both are derived from Kodi's log
                # file, so if that log stops being readable — renamed on a Kodi
                # upgrade, home directory moved, metrics unit broken — they would
                # report zero forever and read as healthy.  This is the "is the
                # smoke detector still plugged in" check.
                alert = "kodi_audio_health_blind";
                expr = ''kodi_audio_log_present == 0'';
                for = "15m";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "{{ $labels.instance }}: Kodi audio health checks are blind.";
                  description = ''
                    The kodi-audio-health-metrics unit on {{ $labels.instance }}
                    cannot read Kodi's log, so kodi_audio_engine_degraded and
                    kodi_audio_engine_wedged cannot fire.  Until this is fixed, a
                    silent Kodi will not alert.
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
