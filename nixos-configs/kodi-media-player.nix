################################################################################
# Kodi standalone mode for TV media playback.
#
# This configuration runs Kodi in fullscreen mode, reading media files directly
# from NFS-mounted storage. The system auto-boots to Kodi and keeps the TV as
# a dumb display. Kodi manages its own media library declaratively without
# needing a separate media server.
################################################################################
{
  config,
  facts,
  host-id,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./kodi-audio-health.nix
  ];

  # Stop the HDMI audio codec runtime-suspending.  snd_hda_intel defaults to
  # power_save=10, so the codec powers down ten seconds after the sink goes
  # idle.  On Haswell the HDMI codec's resume path is coupled to i915 display
  # power through the audio component, which makes "codec suspended" and
  # "display link just dropped" a bad pair of states to be in at once — the
  # resume can fail and leave the sink unusable.
  #
  # There is nothing to save here.  This host is a mains-powered media player
  # that exists to keep an audio sink open.
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=0 power_save_controller=N
  '';
  # Kodi deployments are location and hardware sensitive; every host that
  # runs Kodi registers a host-specific alias.  Location-specific aliases
  # (e.g. "kodi-living-room") should be declared on the host directly, as
  # the same kodi-media-player config may be imported by multiple hosts.
  networking.dnsAliases = [ "kodi-${host-id}" ];

  # Configure NFS mount for media files.
  nfsConsumerFacts = {
    enable = true;
    provider = {
      remoteHost = "silicon.${facts.network.domain}";
      vpnHost = "silicon-nas.${facts.network.domain}";
      providerHostId = "silicon";
      wgPort = 51821;
    };
  };
  services.kodi-standalone = {
    enable = true;
    package = pkgs.kodi.withPackages (
      kodiPkgs: with kodiPkgs; [
        inputstream-adaptive
        inputstream-ffmpegdirect
      ]
    );
    # Move off Kodi's stock 8080, which is one of the most contended numbers
    # there is.  In this repository alone: hosts with "goss" in
    # networking.monitors run a proxy on 8080 (nixos-modules/goss-exporter.nix),
    # nixos-configs/openhab.nix moved to 8085 to get out of its way, and
    # nixos-configs/jenkins-github-webhook-test.nix carries a standing TODO
    # about the same clash.  Kodi hosts do not run goss today, so this is
    # pre-emptive rather than a fix for a live collision.
    #
    # 18080 reads as "8080, moved" so it stays recognisable as the web port,
    # and it sits below the ephemeral range (32768-60999 on these hosts) where
    # a fixed listener cannot lose a race to an outbound connection.
    #
    # Consequence for humans: the Kodi iOS remote talks direct HTTP rather than
    # going through the reverse proxy, so it needs this port set in the app.
    # The HTTPS entry point below is unaffected.
    webserverPort = 18080;
    advancedSettings = {
      services = {
        # Enable web server for remote control via mobile apps.
        webserver = "true";

        # Disable authentication for JSON-RPC access.
        webserverauthentication = "false";

        # Allow remote control from applications on other systems (needed for
        # iOS app).
        esallinterfaces = "true";
      };
      addons = {
        # Allow installation of addon dependencies without prompts.
        unknownsources = "true";
      };
      # No <audio> block here on purpose.  This previously carried
      # volumeamplification = "12.0", commented as a global +12dB boost.  It was
      # neither: Kodi's advancedsettings parser has no volumeamplification key
      # at all (see AdvancedSettings.cpp, which reads only applydrc,
      # limiterhold, limiterrelease and friends out of <audio>), so the element
      # was silently ignored.  Volume amplification is a *per-video* player
      # setting stored in MyVideos*.db, reachable only through the playback OSD.
      #
      # Do not reintroduce it.  Amplification is applied ahead of Kodi's
      # limiter, so raising it to compensate for a quiet disc drives the mix
      # into clipping and the limiter then ducks dialogue under loud music --
      # the opposite of the intended effect.  DVD rips are simply mastered
      # quiet; the TV's volume control is the correct remedy.  See
      # troubleshooting-methods.org, "Kodi: music and effects drown out
      # dialogue".
    };
    guiSettings = {
      # "Keep audio device alive" — 153722867 is the "Always" option (the
      # values are a minutes count, with this sentinel standing in for "never
      # suspend"; confirm against Settings.GetSettings over JSON-RPC rather
      # than assuming).  The stock value is 1, meaning one minute of silence
      # and then CActiveAE releases the sink.
      #
      # Every one of those release/reacquire cycles is a chance for the audio
      # engine to deadlock, and on this host they are driven by an HDMI link
      # that flaps on its own schedule.  Holding the device open removes the
      # cycle rather than trying to survive it.  The cost is a continuous
      # inaudible signal on the HDMI sink, which is exactly what we want on a
      # box whose only job is playing to that sink.
      "audiooutput.streamsilence" = 153722867;
    };
    addonSettings = {
      "plugin.video.jellyfin" = {
        ipaddress = "localhost";
        port = "8096";
        https = "false";
        sslverify = "true";
      };
      "inputstream.ffmpegdirect" = {
        streamselection = "0";
      };
      "inputstream.adaptive" = {
        DECRYPTERPATH = "special://home/cdm";
      };
    };
    enabledAddons = [
      "plugin.video.jellyfin"
      "inputstream.adaptive"
      "inputstream.ffmpegdirect"
    ];
    mediaSources = {
      video = [
        {
          name = "Media Library";
          path = "/mnt/kodi-media/";
        }
        {
          name = "NextCloud Uploads";
          path = "/mnt/nextcloud-shared-media/";
        }
      ];
    };
    # Loku (on silicon) writes browser-compat .compat.mp4 copies beside the
    # MakeMKV masters.  Without the exclude, every movie shows twice.  The scan
    # exclude guards any future library scrape.
    videoExcludeFromScan = [ "\\.compat\\.mp4$" ];
    videoExcludeFromListing = [ "\\.compat\\.mp4$" ];
  };

  # Expose Kodi's web interface for remote control via mobile apps.
  # kodi-lv = Kodi in the living room.
  services.https.fqdns."kodi-living-room.${facts.network.domain}" = {
    enable = true;
    internalPort = config.services.kodi-standalone.webserverPort;
  };

  # Open Kodi's web server port for direct HTTP access.  Required for iOS app
  # remote control: the Kodi iOS app does not support HTTPS endpoints and
  # requires direct HTTP access.  Android HTTPS support is not known.
  networking.firewall.allowedTCPPorts = [
    config.services.kodi-standalone.webserverPort
  ];

  # Add kodi user to media-shared group (created by nfs-consumer-facts).
  users.users.${config.services.kodi-standalone.systemUser}.extraGroups = [
    "media-shared"
    # Serial device access for USB CEC adapter (/dev/ttyACM0).
    "dialout"
  ];

  # Pre-configure Kodi for the kodi user.
  home-manager.users.${config.services.kodi-standalone.systemUser} = {
    home.stateVersion = "25.11";

    # Configure WirePlumber to prefer HDMI audio output over analog.
    # This ensures audio routes to the TV via HDMI instead of the Mac Mini's
    # built-in speakers.
    xdg.configFile."wireplumber/main.lua.d/51-hdmi-default.lua".text = ''
      -- Set HDMI audio as the default sink.
      -- Matches HDA Intel HDMI devices and increases their priority.
      rule = {
        matches = {
          {
            { "node.name", "matches", "alsa_output.pci-0000_00_03.0.hdmi-*" },
          },
        },
        apply_properties = {
          ["priority.session"] = 2000,  -- Higher than default 1009
          ["node.default"] = true,
        },
      }

      table.insert(alsa_monitor.rules, rule)
    '';

    # Set HDMI audio sink volume to 100% on startup.
    systemd.user.services.set-hdmi-volume = {
      Unit = {
        Description = "Set HDMI audio volume to 100%";
        After = [ "pipewire.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.pulseaudioFull}/bin/pactl set-sink-volume alsa_output.pci-0000_00_03.0.hdmi-stereo 100%";
        RemainAfterExit = false;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
