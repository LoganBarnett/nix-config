################################################################################
# programs.stats (macOS) — Stats (exelban/stats), the menu bar system monitor,
# with its preferences declared as typed options.
#
# Stats keeps its settings in the eu.exelban.Stats defaults domain, so the
# options below render into system.defaults.CustomUserPreferences and land
# through nix-darwin's ordinary user-defaults write.  Two quirks shape the rest
# of this module:
#
# - Stats snapshots the whole domain into an in-memory cache at launch and never
#   re-reads it, so a running instance ignores anything written here until it is
#   relaunched.  Activation therefore relaunches Stats when, and only when, the
#   rendered preferences differ from the previous activation.
#
# - The clock list is stored as a Data blob of JSON, which CustomUserPreferences
#   cannot express (nix-darwin's plist generator has no data type), so it is
#   written separately with `defaults write -data`.
#
# Stats ships with a connectivity check that pings 1.1.1.1 over ICMP once a
# second.  macOS's unprivileged ping reports every echo reply the host receives,
# so those replies surface in any ping session as a spurious "(DUP!)" from
# 1.1.1.1.  An empty modules.network.connectivity.icmpHost is Stats' documented
# off switch for the check.
#
# Key shapes (Stats 3.0.15): "<Module>_widget" is a comma-joined list of widget
# raw values (line_chart, bar_chart, ...), whereas the matching
# "<Module>_<Case>_position" ordering keys use the Swift enum case name
# (lineChart, barChart, ...).  Widget settings are "<Prefix>_<raw>_<setting>",
# where the prefix is the module name unless the module's config.plist gives
# that widget a Title (Disk's mini widget is "SSD_mini_color", for instance).
# The tables in the let block encode those mappings.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.stats;
  domain = "eu.exelban.Stats";
  user = config.system.primaryUser;
  appPath = "/Applications/Nix Apps/Stats.app";
  markerFile = "/var/lib/stats/prefs.json";

  # A nullable option whose null means "write nothing; keep Stats' default".
  opt =
    type: statsDefault: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      description = "${description}  Stats' own default is ${statsDefault}; null leaves the preference unwritten.";
    };

  # Stats' SColor keys minus the two separator placeholders it uses in its
  # menus.  Some widgets reject a few of these (most mini, bar and line charts
  # refuse "pressure"; line charts refuse "cluster") and silently fall back to
  # their default.
  colorType = types.enum [
    "utilization"
    "pressure"
    "cluster"
    "system"
    "monochrome"
    "clear"
    "white"
    "black"
    "gray"
    "secondGray"
    "darkGray"
    "lightGray"
    "red"
    "secondRed"
    "green"
    "secondGreen"
    "blue"
    "secondBlue"
    "yellow"
    "secondYellow"
    "orange"
    "secondOrange"
    "purple"
    "secondPurple"
    "brown"
    "secondBrown"
    "cyan"
    "magenta"
    "pink"
    "teal"
    "indigo"
  ];
  historyCountType = types.enum [
    30
    60
    90
    120
  ];
  readerIntervalType = types.enum [
    1
    2
    3
    5
    10
    15
    30
    60
  ];

  # Widget settings shared by every module that offers the widget.  Option
  # names are exactly Stats' setting suffixes, so a key is rendered as
  # "<prefix>_<widget raw value>_<option name>".
  widgetOptions = {
    lineChart = {
      box = opt types.bool "true" "Draw the chart inside a box.";
      frame = opt types.bool "false" "Draw a frame around the chart.";
      color = opt colorType "\"system\"" "Chart colour.";
      historyCount = opt historyCountType "60" "Number of reads kept in the chart.";
      label = opt types.bool "false" "Show the module label beside the chart.";
      scale = opt (types.enum [
        "none"
        "linear"
        "square"
        "cube"
        "logarithmic"
        "fixed"
      ]) "\"none\"" "Vertical scaling of the chart.";
      valueColor = opt types.bool "false" "Colourise the value.";
    };
    barChart = {
      box = opt types.bool "true" "Draw the chart inside a box.";
      frame = opt types.bool "false" "Draw a frame around the chart.";
      color = opt colorType "\"system\"" "Chart colour.";
    };
    pieChart = {
      label = opt types.bool "false" "Show the value inside the chart.";
    };
    mini = {
      color = opt colorType "\"monochrome\"" "Widget colour.";
    };
    networkChart = {
      frame = opt types.bool "false" "Draw a frame around the chart.";
      historyCount = opt historyCountType "60" "Number of reads kept in the chart.";
    };
    speed = {
      icon = opt (types.enum [
        "none"
        "dots"
        "arrows"
        "chars"
      ]) "\"dots\"" "Pictogram shown next to the speeds.";
      valueColor = opt (types.enum [
        "none"
        "default"
        "transparent"
        "constant"
      ]) "\"none\"" "How the speed values are coloured.";
    };
    battery = {
      additional = opt (types.enum [
        "none"
        "innerPercentage"
        "percentage"
        "time"
        "percentageAndTime"
        "timeAndPercentage"
      ]) "\"none\"" "Additional information shown next to the battery icon.";
      color = opt types.bool "false" "Colourise the battery level.";
      hideAdditionalWhenFull =
        opt types.bool "true"
          "Hide the additional information while the battery is full.";
      xlSize = opt types.bool "false" "Draw the battery icon at XL size.";
    };
    batteryDetails = {
      mode = opt (types.enum [
        "percentage"
        "time"
        "percentageAndTime"
        "timeAndPercentage"
      ]) "\"percentage\"" "Which details to show.";
    };
    # Stats calls this widget "sensors" in the preference keys even though it
    # is the generic stacked-values widget used by the Clock and Bluetooth
    # modules too.
    sensors = {
      mode = opt (types.enum [
        "automatic"
        "oneRow"
        "twoRows"
      ]) "\"automatic\"" "Row layout of the stacked values.";
      monospacedFont = opt types.bool "false" "Use a monospaced font.";
    };
  };

  # Widget raw value → Swift enum case name, as used by the ordering keys.
  widgetCase = {
    label = "label";
    mini = "mini";
    line_chart = "lineChart";
    bar_chart = "barChart";
    pie_chart = "pieChart";
    network_chart = "networkChart";
    speed = "speed";
    battery = "battery";
    battery_details = "batteryDetails";
    sensors = "stack";
    memory = "memory";
    tachometer = "tachometer";
    state = "state";
    text = "text";
  };

  # Cosmetic set → widget raw value used in its setting keys.
  widgetRaw = {
    lineChart = "line_chart";
    barChart = "bar_chart";
    pieChart = "pie_chart";
    mini = "mini";
    networkChart = "network_chart";
    speed = "speed";
    battery = "battery";
    batteryDetails = "battery_details";
    sensors = "sensors";
  };

  # Per module: Stats' key name, the widgets its config.plist offers (raw
  # values), the cosmetic sets that apply, and the Title overrides that change
  # a widget's key prefix away from the module name.
  moduleTable = {
    battery = {
      name = "Battery";
      widgets = [
        "label"
        "mini"
        "bar_chart"
        "battery"
        "battery_details"
      ];
      cosmetics = [
        "mini"
        "barChart"
        "battery"
        "batteryDetails"
      ];
      titles.mini = "BAT";
    };
    bluetooth = {
      name = "Bluetooth";
      widgets = [
        "label"
        "sensors"
      ];
      cosmetics = [ "sensors" ];
      titles = { };
    };
    cpu = {
      name = "CPU";
      widgets = [
        "label"
        "mini"
        "line_chart"
        "bar_chart"
        "pie_chart"
        "tachometer"
      ];
      cosmetics = [
        "mini"
        "lineChart"
        "barChart"
        "pieChart"
      ];
      titles = { };
    };
    clock = {
      name = "Clock";
      widgets = [
        "label"
        "sensors"
      ];
      cosmetics = [ "sensors" ];
      titles = { };
    };
    disk = {
      name = "Disk";
      widgets = [
        "label"
        "mini"
        "bar_chart"
        "pie_chart"
        "memory"
        "speed"
        "network_chart"
        "text"
      ];
      cosmetics = [
        "mini"
        "barChart"
        "networkChart"
        "pieChart"
        "speed"
      ];
      titles = {
        mini = "SSD";
        barChart = "SSD";
        networkChart = "SSD";
      };
    };
    gpu = {
      name = "GPU";
      widgets = [
        "label"
        "mini"
        "line_chart"
        "bar_chart"
        "tachometer"
        "text"
      ];
      cosmetics = [
        "mini"
        "lineChart"
        "barChart"
      ];
      titles = { };
    };
    network = {
      name = "Network";
      widgets = [
        "label"
        "speed"
        "network_chart"
        "state"
        "text"
      ];
      cosmetics = [
        "speed"
        "networkChart"
      ];
      titles = { };
    };
    ram = {
      name = "RAM";
      widgets = [
        "label"
        "mini"
        "line_chart"
        "bar_chart"
        "pie_chart"
        "memory"
        "tachometer"
        "text"
        "state"
      ];
      cosmetics = [
        "mini"
        "lineChart"
        "barChart"
        "pieChart"
      ];
      titles = { };
    };
    remote = {
      name = "Remote";
      widgets = [
        "label"
        "state"
      ];
      cosmetics = [ ];
      titles = { };
    };
    sensors = {
      name = "Sensors";
      widgets = [
        "label"
        "mini"
        "sensors"
        "bar_chart"
      ];
      cosmetics = [
        "mini"
        "barChart"
        "sensors"
      ];
      titles = {
        mini = "Sensor";
        barChart = "FAN";
      };
    };
  };

  # Options that only one module has.
  moduleExtraOptions = {
    cpu = {
      clustersGroup =
        opt types.bool "false"
          "Group cores by cluster (efficiency and performance).";
      hyperthreading = opt types.bool "false" "Show hyper-threading cores.";
      splitValue =
        opt types.bool "false"
          "Split the value into system and user shares.";
      usagePerCore = opt types.bool "false" "Show usage per core.";
    };
    network.connectivity = {
      mode = opt (types.enum [
        "icmp"
        "http"
      ]) "\"icmp\"" "Probe used for the connectivity indicator.";
      icmpHost =
        opt types.str "\"1.1.1.1\""
          "Host pinged by the ICMP probe once per interval.  An empty string disables the probe.";
      httpHost =
        opt types.str "\"https://google.com\""
          "URL fetched by the HTTP probe.";
      interval = opt readerIntervalType "1" "Seconds between probes.";
    };
  };

  moduleOptions =
    mname: spec:
    {
      enable =
        opt types.bool "per module"
          "Whether the ${spec.name} module is active.";
      widgets =
        opt (types.listOf (types.enum spec.widgets)) "per module"
          "Widgets shown in the menu bar for ${spec.name}.  An empty list shows none.";
      widgetOrder =
        opt (types.listOf (types.enum spec.widgets)) "unordered"
          "Left-to-right order of ${spec.name}'s widgets in the menu bar; list every widget the module offers.";
      oneView =
        opt types.bool "false"
          "Merge ${spec.name}'s widgets into one menu bar item.";
    }
    // genAttrs spec.cosmetics (set: widgetOptions.${set})
    // (moduleExtraOptions.${mname} or { });

  modulePrefs =
    mname: spec:
    let
      m = cfg.modules.${mname};
      prefix = set: spec.titles.${set} or spec.name;
      cosmetic =
        set:
        mapAttrs' (
          o: v: nameValuePair "${prefix set}_${widgetRaw.${set}}_${o}" v
        ) m.${set};
      positions =
        if m.widgetOrder == null then
          { }
        else
          listToAttrs (
            imap0 (
              i: w: nameValuePair "${spec.name}_${widgetCase.${w}}_position" i
            ) m.widgetOrder
          );
    in
    {
      "${spec.name}_state" = m.enable;
      "${spec.name}_widget" =
        if m.widgets == null then null else concatStringsSep "," m.widgets;
      "${spec.name}_oneView" = m.oneView;
    }
    // positions
    // foldl' (acc: set: acc // cosmetic set) { } spec.cosmetics;

  extraPrefs = {
    CPU_clustersGroup = cfg.modules.cpu.clustersGroup;
    # Stats misspells this key; it has to match what the app reads.
    CPU_hyperhreading = cfg.modules.cpu.hyperthreading;
    CPU_splitValue = cfg.modules.cpu.splitValue;
    CPU_usagePerCore = cfg.modules.cpu.usagePerCore;
    Network_connectivityMode = cfg.modules.network.connectivity.mode;
    Network_ICMPHost = cfg.modules.network.connectivity.icmpHost;
    Network_HTTPHost = cfg.modules.network.connectivity.httpHost;
    Network_updateICMPInterval = cfg.modules.network.connectivity.interval;
  };

  globalPrefs = {
    dockIcon = cfg.dockIcon;
    "update-interval" = cfg.updateCheckInterval;
  }
  // optionalAttrs cfg.setupCompleted {
    setupProcess = true;
    runAtLoginInitialized = true;
    LaunchAtLoginNext = true;
  };

  prefs = filterAttrs (_: v: v != null) (
    globalPrefs // extraPrefs // concatMapAttrs modulePrefs moduleTable
  );

  # Stats identifies clocks by UUID; a stable one derived from the name keeps
  # the list identical across rebuilds without the config having to carry
  # random strings.
  clockId =
    name:
    let
      h = toUpper (hashString "sha256" name);
    in
    concatStringsSep "-" [
      (substring 0 8 h)
      (substring 8 4 h)
      (substring 12 4 h)
      (substring 16 4 h)
      (substring 20 12 h)
    ];

  clockType = types.submodule (
    { config, ... }:
    {
      options = {
        enabled = mkOption {
          type = types.bool;
          default = true;
          description = "Whether the clock is shown.";
        };
        name = mkOption {
          type = types.str;
          description = "Display name of the clock.";
        };
        format = mkOption {
          type = types.str;
          description = "DateFormatter pattern for the clock text, such as \"HH:mm\".";
        };
        tz = mkOption {
          type = types.str;
          description = "Time zone: \"local\", a zone identifier such as \"Europe/Kyiv\", or a UTC offset such as \"0\" or \"-4:30\".";
        };
        calendar = mkOption {
          type = types.str;
          default = "gregorian";
          description = "Calendar identifier.";
        };
        id = mkOption {
          type = types.str;
          default = clockId config.name;
          description = "Identifier Stats uses to track the clock across edits.  Derived from the name unless set; keep the existing id when adopting a clock that was created in the UI.";
        };
      };
    }
  );

  clocksJson = builtins.toJSON (
    map (c: {
      inherit (c)
        id
        enabled
        name
        format
        tz
        calendar
        ;
    }) cfg.clocks
  );

  # Everything the activation writes, so a change in any of it can be
  # detected against the marker left by the previous activation.
  prefsFile = pkgs.writeText "stats-prefs.json" (
    builtins.toJSON {
      inherit prefs;
      clocks = cfg.clocks;
    }
  );

  # nix-darwin's own form for running a user-level command from the root
  # activation script.  launchctl and sudo are macOS builtins with no Nix
  # counterpart, hence the absolute paths.
  asUser =
    cmd:
    ''/bin/launchctl asuser "$(${pkgs.coreutils}/bin/id --user -- ${escapeShellArg user})" /usr/bin/sudo --user=${escapeShellArg user} -- ${cmd}'';
in
{
  options.programs.stats = {
    enable = mkEnableOption ''
      Stats (exelban/stats), the menu bar system monitor, with its preferences
      rendered from the options below into the eu.exelban.Stats defaults
      domain'';

    package = mkPackageOption pkgs "stats" { };

    dockIcon = opt types.bool "false" "Show the Stats icon in the Dock.";

    updateCheckInterval =
      opt
        (types.enum [
          "Silent"
          "At start"
          "Once per day"
          "Once per week"
          "Once per month"
          "Never"
        ])
        "\"Silent\""
        "How often Stats checks for its own updates.  Nix manages the package, so \"Never\" is the sensible value.";

    setupCompleted = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Mark the first-run setup as done.  Stats treats the mere existence of
        its setupProcess, runAtLoginInitialized and LaunchAtLoginNext keys as
        "already onboarded", which suppresses the setup wizard, the periodic
        support prompt and the legacy login-item migration.  Launch at login
        itself is not a preference (Stats registers with SMAppService), so it
        is not managed here.
      '';
    };

    restartOnChange = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Relaunch a running Stats during activation when the rendered
        preferences differ from the previous activation.  Stats only reads
        its preferences at launch, so without this a change waits for the
        next manual relaunch.
      '';
    };

    clocks = mkOption {
      type = types.listOf clockType;
      default = [ ];
      description = ''
        Clocks shown by the Clock module.  An empty list leaves Stats' own
        list untouched.
      '';
    };

    modules = mapAttrs moduleOptions moduleTable;
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    system.defaults.CustomUserPreferences.${domain} = prefs;

    system.activationScripts.postActivation.text = ''
      echo "Configuring Stats..." >&2
      ${optionalString (cfg.clocks != [ ]) ''
        # The clock list is JSON stored as a Data blob, which `defaults write
        # -data` takes as a hex string.
        stats_clocks_hex=$(
          printf '%s' ${escapeShellArg clocksJson} \
            | ${pkgs.coreutils}/bin/od --address-radix=n --format=x1 --output-duplicates \
            | ${pkgs.coreutils}/bin/tr --delete ' \n'
        )
        ${asUser ''/usr/bin/defaults write ${domain} Clock_list -data "$stats_clocks_hex"''}
      ''}
      ${optionalString cfg.restartOnChange ''
        # A missing marker (first activation) also makes cmp exit non-zero,
        # which is the branch we want.
        if ! ${pkgs.diffutils}/bin/cmp --silent ${prefsFile} ${markerFile}; then
          ${pkgs.coreutils}/bin/mkdir --parents ${dirOf markerFile}
          ${pkgs.coreutils}/bin/cp ${prefsFile} ${markerFile}
          # pgrep is a macOS builtin with no Nix counterpart, hence the
          # absolute path.  -x: match the whole process name (no long form
          # exists).
          stats_running() {
            /usr/bin/pgrep -x Stats >/dev/null
          }
          if stats_running; then
            echo "Relaunching Stats to pick up its new preferences..." >&2
            # osascript -e: run the script text given as the argument (no long
            # form exists).
            ${asUser "/usr/bin/osascript -e 'tell application \"Stats\" to quit'"} || true
            # Quit is asynchronous; wait for the process to go away before
            # relaunching so the relaunch is not swallowed by the shutdown.
            for _ in $(${pkgs.coreutils}/bin/seq 1 10); do
              stats_running || break
              ${pkgs.coreutils}/bin/sleep 1
            done
            # open -a: launch the named application (no long form exists).
            ${asUser "/usr/bin/open -a ${escapeShellArg appPath}"} || true
          fi
        fi
      ''}
    '';
  };
}
