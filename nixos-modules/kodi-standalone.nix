################################################################################
# Runs Kodi in standalone mode for TV playback.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf mkOption;
  cfg = config.services.kodi-standalone;
  jsonRpcUrl = "http://localhost:${toString cfg.webserverPort}/jsonrpc";
  # Kodi's JSON-RPC web server comes up a little after the process does, so
  # anything driving it has to poll first.  Shared by every unit below that
  # talks to the API.
  waitForJsonRpc = ''
    for i in {1..30}; do
      if ${pkgs.curl}/bin/curl \
           --silent \
           ${jsonRpcUrl} &>/dev/null;
      then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
in
{
  options = {
    services.kodi-standalone = {
      enable = mkEnableOption "Run Kodi in standalone mode as a media center interface.";
      systemUser = mkOption {
        type = lib.types.str;
        default = "kodi";
        description = ''
          The user to auto-login as.
        '';
      };
      systemGroup = mkOption {
        type = lib.types.str;
        default = "kodi";
        description = ''
          The group of the auto-login user.
        '';
      };
      package = mkOption {
        type = lib.types.package;
        description = ''
          The Kodi package to use.
        '';
      };
      webserverPort = mkOption {
        type = lib.types.port;
        default = 8080;
        description = ''
          Port for Kodi's built-in web server, which also serves the JSON-RPC
          API.

          This is the single source of truth for the port: it is written into
          advancedsettings.xml as services.webserverport, so Kodi is told the
          value rather than left on its default and assumed to have stayed
          there.  Consumers should read this option instead of hardcoding a
          number — the units in this module that drive JSON-RPC do, and so
          should any firewall rule or reverse-proxy target for the web
          interface.

          It cannot be set through the guiSettings option: that applies over
          JSON-RPC, which means it needs a working port to reach the setting
          that decides the port.  advancedsettings.xml is read at startup,
          before the web server binds, so it is the only lever that works.

          The default matches Kodi's own so that leaving this alone is not a
          surprise.  Be aware that 8080 is heavily contended, though — it is a
          popular default for unrelated software, so on a host running much
          else it is worth moving somewhere quieter.  Prefer a port below the
          ephemeral range (net.ipv4.ip_local_port_range, typically 32768 and
          up): a fixed listener inside that range can lose a race to an
          outbound connection that grabbed the port first.
        '';
      };
      advancedSettings = mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
        default = { };
        description = ''
          Advanced Kodi settings to configure via advancedsettings.xml.
          These settings override guisettings.xml and are hidden from the UI.

          Settings are specified as nested attrsets matching the XML structure.
          See https://kodi.wiki/view/Advancedsettings.xml for available settings.
        '';
        example = {
          services = {
            webserver = "true";
            esallinterfaces = "true";
          };
          addons = {
            unknownsources = "true";
          };
        };
      };
      peripheralSettings = mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
        default = { };
        description = ''
          Peripheral-specific settings for Kodi's peripheral_data directory.
          Each key is a peripheral filename (without .xml), and the value is
          an attrset of setting-id → value pairs.

          Uses <setting id="key" value="value"/> format (value as attribute).
        '';
      };
      addonSettings = mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
        default = { };
        description = ''
          Addon-specific settings to configure via userdata/addon_data/*/settings.xml.
          These files use the <settings version="2"> format with <setting id="key">value</setting>.

          Settings are specified as addon-path -> setting-id -> value.
        '';
        example = {
          "plugin.video.jellyfin" = {
            ipaddress = "localhost";
            port = "8096";
            https = "false";
          };
          "inputstream.adaptive" = {
            DECRYPTERPATH = "special://home/cdm";
          };
        };
      };
      guiSettings = mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.bool
            lib.types.int
            lib.types.str
          ]
        );
        default = { };
        description = ''
          Settings from userdata/guisettings.xml, applied via JSON-RPC after
          Kodi starts.

          Unlike advancedsettings.xml, guisettings.xml is owned and rewritten
          by Kodi itself — it cannot be managed as a home-manager file without
          Kodi clobbering it on every shutdown.  Driving the same values
          through Settings.SetSettingValue at startup is the only way to hold
          them declaratively; Kodi then persists them normally.

          Values are typed: booleans, integers and strings all map onto their
          JSON equivalents.  Enum-valued settings take the integer the setting
          definition assigns, not the label — consult
          share/kodi/system/settings/settings.xml in the Kodi package, or
          query Settings.GetSettings over JSON-RPC on a running instance.
        '';
        example = {
          "audiooutput.streamsilence" = 153722867;
          "audiooutput.channels" = 1;
        };
      };
      enabledAddons = mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          List of addon IDs to enable automatically on Kodi startup via JSON-RPC.
        '';
        example = [
          "plugin.video.jellyfin"
          "inputstream.adaptive"
          "inputstream.ffmpegdirect"
        ];
      };
      mediaSources = mkOption {
        type = lib.types.attrsOf (
          lib.types.listOf (
            lib.types.submodule {
              options = {
                name = mkOption {
                  type = lib.types.str;
                  description = "Display name for this media source.";
                };
                path = mkOption {
                  type = lib.types.str;
                  description = "File path or network location for this media source.";
                };
              };
            }
          )
        );
        default = { };
        description = ''
          Declarative media sources to configure via sources.xml.
          Sources are organized by media type (video, music, pictures, programs).

          This allows fully declarative configuration of Kodi's media library
          without requiring interactive setup through the UI.
        '';
        example = {
          video = [
            {
              name = "Movies";
              path = "/mnt/kodi-media/Movies/";
            }
            {
              name = "TV Shows";
              path = "/mnt/kodi-media/TV/";
            }
          ];
          music = [
            {
              name = "Music Library";
              path = "/mnt/kodi-media/Music/";
            }
          ];
        };
      };
    };
  };
  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        age.secrets.kodi-passphrase = {
          generator.script = "long-passphrase";
          group = cfg.systemGroup;
          mode = "0440";
          rekeyFile = ../secrets/kodi-passphrase.age;
        };
        age.secrets.kodi-passphrase-hashed = {
          generator = {
            script = "long-passphrase-hashed";
            dependencies = [
              config.age.secrets.kodi-passphrase
            ];
          };
        };
        environment.systemPackages = [
          # Allow us to adjust the volume.  Not sure if we're using Alsa or
          # PulseAudio, so we include them both.
          pkgs.alsa-utils
          # Allow us to adjust the volume.  Not sure if we're using Alsa or
          # PulseAudio, so we include them both.
          pkgs.pamixer
          pkgs.pulseaudioFull
          # Can be useful for querying some of Kodi's databases for debugging
          # purposes.
          pkgs.sqlite
        ];
        users.users.${cfg.systemUser} = {
          isNormalUser = true;
          group = cfg.systemGroup;
          extraGroups = [
            "video"
            "audio"
            "input"
            "render"
          ];
          hashedPasswordFile = config.age.secrets.kodi-passphrase-hashed.path;
        };
        users.groups.${cfg.systemGroup} = { };
        services.displayManager = {
          enable = true;
          autoLogin = {
            enable = true;
            user = cfg.systemUser;
          };
        };
        # Hide the mouse cursor.
        services.unclutter-xfixes.enable = true;
        services.xserver = {
          enable = true;
          # Disable screen blanking - we want continuous playback.
          serverFlagsSection = ''
            Option "BlankTime" "0"
            Option "StandbyTime" "0"
            Option "SuspendTime" "0"
            Option "OffTime" "0"
          '';
          displayManager = {
            lightdm.enable = true;
            # Turn off screen saver and power management.
            sessionCommands = ''
              xset s off
              xset -dpms
              xset s noblank
            '';
            session = [
              {
                name = "kodi";
                manage = "windowManager";
                start = ''
                  ${pkgs.openbox}/bin/openbox-session &
                  systemctl --user start kodi.service
                  waitPID=$!
                '';
              }
            ];
          };
          windowManager.openbox.enable = true;
        };
        systemd.user.services.kodi = {
          enable = true;
          description = "Kodi Media Center";
          after = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            ExecStart = ''
              ${cfg.package}/bin/kodi --standalone
            '';
            Restart = "always";
            # A Kodi whose audio engine has deadlocked blocks in its own
            # shutdown path waiting on the wedged thread, so it sits there for
            # the full 90s default before systemd gives up and SIGKILLs it —
            # which is exactly the state you are usually in when restarting it.
            # Twenty seconds is well clear of a healthy shutdown.
            TimeoutStopSec = "20s";
            Environment = "XDG_RUNTIME_DIR=%t";
          };
        };
        # Tell Kodi which port to serve the web interface and JSON-RPC API on.
        #
        # This lands in advancedsettings.xml, which reaches the settings system
        # through CSettings::LoadHidden() rather than any key-by-key parser in
        # AdvancedSettings.cpp — so any real setting id works here, and only
        # real setting ids work.  ("services.webserverport" is one; see the
        # note on volumeamplification in nixos-configs/kodi-media-player.nix
        # for what happens when you invent one that is not.)
        services.kodi-standalone.advancedSettings.services.webserverport =
          toString cfg.webserverPort;

        # Enable hardware acceleration for video playback.
        hardware.graphics.enable = true;
      }
      (mkIf (cfg.enabledAddons != [ ]) {
        # Service to enable addons via JSON-RPC after Kodi starts.
        systemd.user.services.kodi-enable-addons = {
          description = "Enable Kodi addons via JSON-RPC";
          after = [ "kodi.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = false;
            ExecStart = pkgs.writeShellScript "kodi-enable-addons" ''
              ${waitForJsonRpc}

              # Enable each addon in the list.
              ${builtins.concatStringsSep "\n" (
                map (addonId: ''
                  ${pkgs.curl}/bin/curl \
                    --silent \
                    --header "Content-Type: application/json" \
                    --data '{
                      "jsonrpc":"2.0",
                      "method":"Addons.SetAddonEnabled",
                      "params":{"addonid":"${addonId}","enabled":true},
                      "id":1
                    }' \
                    ${jsonRpcUrl}
                '') cfg.enabledAddons
              )}
            '';
          };
        };
      })
      (mkIf (cfg.guiSettings != { }) {
        # Apply guisettings.xml values via JSON-RPC once Kodi is up.  See the
        # guiSettings option description for why this cannot be a managed file.
        systemd.user.services.kodi-gui-settings = {
          description = "Apply Kodi GUI settings via JSON-RPC";
          after = [ "kodi.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = false;
            ExecStart = pkgs.writeShellScript "kodi-gui-settings" ''
              ${waitForJsonRpc}

              ${builtins.concatStringsSep "\n" (
                lib.mapAttrsToList (settingId: value: ''
                  ${pkgs.curl}/bin/curl \
                    --silent \
                    --header "Content-Type: application/json" \
                    --data '{
                      "jsonrpc":"2.0",
                      "method":"Settings.SetSettingValue",
                      "params":{
                        "setting":"${settingId}",
                        "value":${builtins.toJSON value}
                      },
                      "id":1
                    }' \
                    ${jsonRpcUrl}
                '') cfg.guiSettings
              )}
            '';
          };
        };
      })
      (mkIf (cfg.advancedSettings != { }) {
        # Generate advancedsettings.xml from the advancedSettings option.
        home-manager.users.${cfg.systemUser} = {
          home.file.".kodi/userdata/advancedsettings.xml".text =
            let
              advancedSettingsXml = ''
                <advancedsettings>
                  ${builtins.concatStringsSep "\n" (
                    lib.mapAttrsToList (section: settings: ''
                      <${section}>
                                    ${builtins.concatStringsSep "\n    " (
                                      lib.mapAttrsToList (name: value: ''<${name}>${value}</${name}>'') settings
                                    )}
                                  </${section}>'') cfg.advancedSettings
                  )}
                </advancedsettings>
              '';
            in
            advancedSettingsXml;
        };
      })
      (mkIf (cfg.addonSettings != { }) {
        # Generate addon settings XML files from the addonSettings option.
        home-manager.users.${cfg.systemUser} = {
          home.file = lib.mapAttrs' (
            addonPath: settings:
            lib.nameValuePair ".kodi/userdata/addon_data/${addonPath}/settings.xml" {
              text = ''
                <settings version="2">
                  ${builtins.concatStringsSep "\n  " (
                    lib.mapAttrsToList (
                      settingId: value: ''<setting id="${settingId}">${value}</setting>''
                    ) settings
                  )}
                </settings>
              '';
            }
          ) cfg.addonSettings;
        };
      })
      (mkIf (cfg.peripheralSettings != { }) {
        home-manager.users.${cfg.systemUser} = {
          home.file = lib.mapAttrs' (
            peripheralName: settings:
            lib.nameValuePair ".kodi/userdata/peripheral_data/${peripheralName}.xml" {
              force = true;
              text = ''
                <settings>
                    ${builtins.concatStringsSep "\n    " (
                      lib.mapAttrsToList (
                        settingId: value: ''<setting id="${settingId}" value="${value}"/>''
                      ) settings
                    )}
                </settings>
              '';
            }
          ) cfg.peripheralSettings;
        };
      })
      (mkIf (cfg.mediaSources != { }) {
        # Generate sources.xml from the mediaSources option.
        home-manager.users.${cfg.systemUser} = {
          home.file.".kodi/userdata/sources.xml".text =
            let
              sourcesXml = ''
                <sources>
                  ${builtins.concatStringsSep "\n  " (
                    lib.mapAttrsToList (mediaType: sources: ''
                      <${mediaType}>
                                    ${builtins.concatStringsSep "\n    " (
                                      map (source: ''
                                        <source>
                                                          <name>${source.name}</name>
                                                          <path pathversion="1">${source.path}</path>
                                                        </source>'') sources
                                    )}
                                  </${mediaType}>'') cfg.mediaSources
                  )}
                </sources>
              '';
            in
            sourcesXml;
        };
      })
    ]
  );
}
