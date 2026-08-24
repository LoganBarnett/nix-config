################################################################################
# Displays Grafana dashboards in a kiosk mode, one fullscreen browser per
# monitor.
#
# Each entry in services.grafana-kiosk.displays is keyed by its RandR output
# name (e.g. "HDMI-1") and yields one grafana-kiosk-<output>.service systemd
# user unit.  The monitor layout and each browser's window position both
# derive from the same x/y declaration, so the two cannot drift apart.  The
# multi-head mechanism is chromium's fullscreen behavior: grafana-kiosk
# launches chromium with --kiosk --start-fullscreen and a --window-position,
# and chromium fullscreens on whichever monitor contains that position.
#
# A root-run health probe on a timer compares the live layout and browser
# processes against the declared configuration, and a goss check surfaces the
# probe's unit result to Prometheus.  This is the active failure signal for
# the degraded states this module tolerates by design (see the setupCommands
# comment below).
################################################################################
{
  config,
  facts,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf mkOption;
  cfg = config.services.grafana-kiosk;
  kiosk-home = config.users.users.${cfg.systemUser}.home;
  kiosk-unit-names = map (output: "grafana-kiosk-${output}") (
    lib.attrNames cfg.displays
  );
  xrandr-arguments = lib.concatLists (
    lib.mapAttrsToList (
      output: display:
      [
        "--output"
        output
        "--mode"
        "${toString display.width}x${toString display.height}"
        "--pos"
        "${toString display.x}x${toString display.y}"
      ]
      ++ lib.optional display.primary "--primary"
      ++ lib.optionals (display.brightness != null) [
        "--brightness"
        (toString display.brightness)
      ]
    ) cfg.displays
  );
  # The same hash that grafana.nix computes, so the Grafana server and the
  # kiosks restart together when a dashboard changes.
  dashboards-hash = builtins.hashString "sha256" (
    builtins.toJSON (
      facts.network.monitoring.grafanaDashboards { inherit lib facts; }
    )
  );
  # The \$( survives into the activation script so the printed hint shows a
  # literal $(id ...) for the reader to paste, rather than expanding at
  # activation time.
  restart-command =
    unit:
    lib.concatStringsSep " " [
      "sudo"
      "--user=${cfg.systemUser}"
      ''XDG_RUNTIME_DIR=/run/user/\$(id --user ${cfg.systemUser})''
      "systemctl --user restart ${unit}.service"
    ];
  # The expected xrandr --query line for a display, e.g.
  # "HDMI-1 connected primary 1920x1080+0+0".
  expected-xrandr-line =
    output: display:
    "${output} connected"
    + lib.optionalString display.primary " primary"
    + " ${toString display.width}x${toString display.height}"
    + "+${toString display.x}+${toString display.y}";
  # Matches the grafana-kiosk wrapper process for a display by its window
  # position, which is unique per display.  The space before the position
  # distinguishes the wrapper's "-window-position 0,0" from the chromium
  # child's "--window-position=0,0".
  expected-process-pattern =
    display:
    "bin/grafana-kiosk -URL .* -window-position "
    + "${toString display.x},${toString display.y}$";
  health-check-invocations = lib.concatLines (
    lib.concatLists (
      lib.mapAttrsToList (output: display: [
        "check_layout ${lib.escapeShellArg (expected-xrandr-line output display)}"
        "check_process ${lib.escapeShellArg (expected-process-pattern display)}"
      ]) cfg.displays
    )
  );
  health-check = pkgs.writeShellApplication {
    name = "grafana-kiosk-health";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.procps
      pkgs.xorg.xrandr
    ];
    text = ''
      # Compare the live X layout and kiosk processes against the declared
      # configuration.  A nonzero exit surfaces through the systemd unit
      # result, which goss reports to Prometheus; the journal carries the
      # specific mismatch.  If X itself is down, the xrandr query fails and
      # the probe fails with it, which is also the correct signal.
      export DISPLAY=:0
      export XAUTHORITY=${kiosk-home}/.Xauthority
      layout="$(xrandr --query)"
      status=0
      check_layout() {
        if ! grep --quiet --fixed-strings "$1" <<< "$layout"; then
          echo "layout mismatch: expected \"$1\"" >&2
          status=1
        fi
      }
      check_process() {
        if ! pgrep --full -- "$1" > /dev/null; then
          echo "no kiosk process matching \"$1\"" >&2
          status=1
        fi
      }
      ${health-check-invocations}
      exit "$status"
    '';
  };
in
{
  options = {
    services.grafana-kiosk = {
      enable = mkEnableOption "Use Grafana-kiosk to display Grafana dashboards in kiosk mode.";
      displays = mkOption {
        default = { };
        description = ''
          Kiosk instances keyed by RandR output name (e.g. "HDMI-1").  One
          systemd user unit named grafana-kiosk-<output>.service is generated
          per entry, and the monitor layout is assembled from the entries'
          geometry into a single xrandr invocation.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              url = mkOption {
                type = lib.types.str;
                description = ''
                  The URL of the Grafana dashboard to display on this output.
                '';
              };
              width = mkOption {
                type = lib.types.ints.positive;
                description = ''
                  Horizontal resolution of the RandR mode to select.
                '';
              };
              height = mkOption {
                type = lib.types.ints.positive;
                description = ''
                  Vertical resolution of the RandR mode to select.
                '';
              };
              x = mkOption {
                type = lib.types.int;
                default = 0;
                description = ''
                  Horizontal position of this output in the virtual screen.
                  Also used as the kiosk browser's window position, which is
                  how each browser lands on its monitor.
                '';
              };
              y = mkOption {
                type = lib.types.int;
                default = 0;
                description = ''
                  Vertical position of this output in the virtual screen.  Also
                  used as the kiosk browser's window position, which is how
                  each browser lands on its monitor.
                '';
              };
              primary = mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Mark this output as the RandR primary.
                '';
              };
              brightness = mkOption {
                type = lib.types.nullOr lib.types.float;
                default = null;
                description = ''
                  Optional software brightness multiplier passed to xrandr.
                  Values above 1.0 brighten at the cost of clipping highlights.
                '';
              };
            };
          }
        );
      };
      systemUser = mkOption {
        type = lib.types.str;
        default = "kiosk";
        description = ''
          The user to auto-login as.
        '';
      };
      systemGroup = mkOption {
        type = lib.types.str;
        default = "kiosk";
        description = ''
          The group of the auto-login user.
        '';
      };
      package = mkOption {
        type = lib.types.package;
        default = pkgs.grafana-kiosk;
      };
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.displays != { };
        message = "services.grafana-kiosk.displays must declare at least one display.";
      }
    ];
    age.secrets.grafana-kiosk-passphrase = {
      generator.script = "long-passphrase";
      group = cfg.systemGroup;
      mode = "0440";
      rekeyFile = ../secrets/grafana-kiosk-passphrase.age;
    };
    age.secrets.grafana-kiosk-passphrase-hashed = {
      generator = {
        script = "long-passphrase-hashed";
        dependencies = [
          config.age.secrets.grafana-kiosk-passphrase
        ];
      };
    };
    users.users.${cfg.systemUser} = {
      isNormalUser = true;
      group = cfg.systemGroup;
      extraGroups = [
        "video"
        "input"
      ];
      hashedPasswordFile = config.age.secrets.grafana-kiosk-passphrase-hashed.path;
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
      # Optional: Disable screen blanking.
      serverFlagsSection = ''
        Option "BlankTime" "0"
        Option "StandbyTime" "0"
        Option "SuspendTime" "0"
        Option "OffTime" "0"
      '';
      displayManager = {
        lightdm.enable = true;
        # Lay out the monitors before the greeter and session start, so each
        # kiosk browser's window position lands on a live output.  LightDM
        # treats a failing display-setup-script as fatal for the seat, so
        # tolerate errors here: the || true only neutralizes the exit code,
        # while xrandr's stderr still lands in LightDM's log.  The degraded
        # result is X's default cloned layout with every kiosk stacked on
        # one screen — still showing a dashboard and recoverable over ssh,
        # where a stopped seat would show nothing at all.  The health probe
        # below turns that degradation into an alert.
        setupCommands = ''
          ${
            lib.escapeShellArgs ([ "${pkgs.xorg.xrandr}/bin/xrandr" ] ++ xrandr-arguments)
          } || true
        '';
        # Optional: Turn off the screen saver and DPMS.
        sessionCommands = ''
          xset s off
          xset -dpms
          xset s noblank
        '';
        session = [
          {
            name = "kiosk";
            manage = "windowManager";
            # The grafana-kiosk user units start via graphical-session.target
            # once the session is up; nothing needs starting by hand here.
            start = ''
              ${pkgs.openbox}/bin/openbox-session &
              waitPID=$!
            '';
          }
        ];
      };
      windowManager.openbox.enable = true;
    };
    systemd.user.services = lib.mapAttrs' (
      output: display:
      lib.nameValuePair "grafana-kiosk-${output}" {
        enable = true;
        description = "Grafana kiosk on ${output}";
        after = [ "network.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            "${cfg.package}/bin/grafana-kiosk"
            "-URL"
            display.url
            "-window-position"
            "${toString display.x},${toString display.y}"
          ];
          Restart = "always";
          Environment = [
            "XDG_RUNTIME_DIR=%t"
            # Disable GPU to reduce memory usage.
            "KIOSK_GPU_ENABLED=false"
          ];
        };
        # Restart the kiosks when dashboards change, using the same hash
        # that grafana.nix uses, so both services restart together on
        # deploy.
        #
        # NOTE: As of 2026-02-26 this does not work.  NixOS's
        # switch-to-configuration script only applies restartTriggers
        # logic to system-scoped units; user services receive only a
        # daemon-reexec.  This is a known missing feature:
        # https://github.com/NixOS/nixpkgs/issues/246611
        # Left in place so it takes effect if/when that issue is resolved.
        restartTriggers = [ dashboards-hash ];
      }
    ) cfg.displays;
    # Print the manual restart commands on every deploy as a reminder, since
    # restartTriggers does not yet fire for user services (see above).
    system.activationScripts.grafana-kiosk-restart-hint = lib.concatLines (
      [ ''echo "To restart the Grafana kiosks manually, run:"'' ]
      ++ map (unit: ''echo "  ${restart-command unit}"'') kiosk-unit-names
    );
    # The health probe runs as root so it can read the kiosk user's X
    # authority cookie; goss itself runs as an unprivileged DynamicUser and
    # cannot.  Goss only reads the probe's unit result.
    systemd.services.grafana-kiosk-health = {
      description = "Grafana kiosk health probe";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe health-check;
      };
    };
    systemd.timers.grafana-kiosk-health = {
      description = "Periodic Grafana kiosk health probe";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Give X and the browsers time to come up before the first probe, so
        # a normal boot does not register a failure.
        OnBootSec = "3min";
        OnUnitActiveSec = "1min";
      };
    };
    services.goss.checks.command."grafana-kiosk-health" = {
      exec = lib.concatStringsSep " " [
        "${pkgs.systemd}/bin/systemctl"
        "show"
        "grafana-kiosk-health.service"
        "--property=Result"
        "--value"
      ];
      exit-status = 0;
      stdout = [ "success" ];
      timeout = 5000;
    };
  };
}
