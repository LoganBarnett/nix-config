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
#
# Options are documented in docs/nix-options.org under
# services.grafana-kiosk.  The runbook for a kiosk host that runs out of
# memory is docs/operations/memory-livelock.org.
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
        "check_layout ${
          lib.escapeShellArg (expected-xrandr-line output display)
        }"
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
      enable =
        mkEnableOption
          "Use Grafana-kiosk to display Grafana dashboards in kiosk mode.";
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
      memoryMax = mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "1200M";
        description = ''
          MemoryMax for each kiosk unit, in systemd size syntax.  Chromium leaks
          slowly over long uptimes, and a Pi with no swap livelocks before the
          kernel OOM killer acts.  At the cap the kernel kills one process in
          the unit, OOMPolicy=kill takes the rest of the browser tree, and
          Restart=always brings the kiosk back.  Swap is denied to a capped unit
          so the cap is a kill, not a spill into swap.  Multiply by the number
          of displays and leave room for X, the exporters, and the kernel.
          Needs the memory cgroup controller, which the Pi firmware disables
          unless the kernel command line enables it.  null sets no cap.
        '';
      };
      maxRuntime = mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "1d";
        example = "12h";
        description = ''
          RuntimeMaxSec for each kiosk unit.  The unit stops after running this
          long and Restart=always starts it again, so chromium gets a fresh
          process tree before a slow leak reaches memoryMax.  null disables the
          periodic restart.
        '';
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
        message =
          "services.grafana-kiosk.displays must declare at least one display.";
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
      hashedPasswordFile =
        config.age.secrets.grafana-kiosk-passphrase-hashed.path;
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
        # one screen -- still showing a dashboard and recoverable over ssh,
        # where a stopped seat would show nothing at all.  The health probe
        # below turns that degradation into an alert.
        setupCommands = ''
          ${
            lib.escapeShellArgs (
              [ "${pkgs.xorg.xrandr}/bin/xrandr" ] ++ xrandr-arguments
            )
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
        # Resource control works in a user unit because user@.service delegates
        # the memory controller to the user manager.
        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            "${cfg.package}/bin/grafana-kiosk"
            "-URL"
            display.url
            "-window-position"
            "${toString display.x},${toString display.y}"
          ];
          Restart = "always";
          # The kernel OOM killer takes one process in the cgroup, which leaves
          # chromium alive with a dead renderer and an error page on the
          # monitor.  Kill the whole tree so Restart brings back a working
          # kiosk.
          OOMPolicy = "kill";
          Environment = [
            "XDG_RUNTIME_DIR=%t"
            # Disable GPU to reduce memory usage.
            "KIOSK_GPU_ENABLED=false"
          ];
        }
        // lib.optionalAttrs (cfg.memoryMax != null) {
          MemoryMax = cfg.memoryMax;
          # The cap exists to kill a leaking browser.  Without this a zram swap
          # device absorbs the leak and the cap never bites.
          MemorySwapMax = "0";
        }
        // lib.optionalAttrs (cfg.maxRuntime != null) {
          RuntimeMaxSec = cfg.maxRuntime;
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
        # Grace period before the first probe, counted from when the timer
        # itself starts -- at boot, and also when a deploy first introduces
        # the timer on a long-running system.
        OnActiveSec = "3min";
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
