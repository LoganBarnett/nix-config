################################################################################
# Logan's Stats layout: which modules show in the menu bar, their widgets and
# cosmetics, and the app-level knobs.  Captured from scandium so every Mac that
# imports this gets the same menu bar, with the ICMP connectivity probe off.
################################################################################
{ ... }:
{
  programs.stats = {
    enable = true;
    dockIcon = true;
    # Nix manages the package, so Stats' own updater has nothing to do.
    updateCheckInterval = "Never";
    setupCompleted = true;
    # The ids are the ones Stats generated when these clocks were created in
    # its UI; keeping them means Stats sees the same entries, not replacements.
    clocks = [
      {
        name = "UTC";
        tz = "0";
        format = "HH:mm+0";
        id = "FF05DB63-A1AF-4210-9DCC-6173ECF67B0B";
      }
      {
        name = "Local";
        tz = "local";
        format = "HH:mm±L";
        id = "595FD95A-7E78-4649-B04D-91AFB9EAA785";
      }
    ];
    modules = {
      battery = {
        enable = true;
        widgets = [
          "battery"
          "battery_details"
        ];
        widgetOrder = [
          "battery"
          "battery_details"
          "label"
          "mini"
          "bar_chart"
        ];
        battery = {
          additional = "none";
          color = true;
          hideAdditionalWhenFull = false;
          xlSize = true;
        };
        batteryDetails.mode = "percentageAndTime";
      };
      bluetooth = {
        enable = true;
        widgets = [ ];
        widgetOrder = [
          "sensors"
          "label"
        ];
      };
      cpu = {
        enable = true;
        widgets = [
          "line_chart"
          "bar_chart"
        ];
        widgetOrder = [
          "bar_chart"
          "line_chart"
          "label"
          "mini"
          "pie_chart"
          "tachometer"
        ];
        oneView = false;
        clustersGroup = false;
        hyperthreading = false;
        splitValue = false;
        usagePerCore = true;
        barChart = {
          box = false;
          color = "utilization";
          frame = true;
        };
        lineChart = {
          box = false;
          color = "utilization";
          frame = true;
          historyCount = 30;
          label = false;
          scale = "none";
          valueColor = true;
        };
        mini.color = "system";
      };
      clock = {
        enable = true;
        widgets = [ "sensors" ];
        widgetOrder = [
          "sensors"
          "label"
        ];
        sensors = {
          mode = "twoRows";
          monospacedFont = true;
        };
      };
      disk = {
        enable = true;
        widgets = [
          "bar_chart"
          "pie_chart"
          "speed"
        ];
        widgetOrder = [
          "pie_chart"
          "speed"
          "mini"
          "label"
          "bar_chart"
          "memory"
          "network_chart"
          "text"
        ];
      };
      gpu = {
        enable = true;
        widgets = [ "mini" ];
      };
      network = {
        enable = true;
        widgets = [
          "speed"
          "network_chart"
        ];
        widgetOrder = [
          "speed"
          "network_chart"
          "label"
          "state"
          "text"
        ];
        oneView = true;
        networkChart = {
          frame = true;
          historyCount = 30;
        };
        speed = {
          icon = "none";
          valueColor = "default";
        };
        # Empty host disables the once-a-second ICMP probe to 1.1.1.1 whose
        # replies otherwise show up as duplicates in every ping session.
        connectivity = {
          icmpHost = "";
          interval = 1;
        };
      };
      ram = {
        enable = true;
        widgets = [ "pie_chart" ];
        widgetOrder = [
          "pie_chart"
          "label"
          "mini"
          "line_chart"
          "bar_chart"
          "memory"
          "tachometer"
          "text"
          "state"
        ];
        barChart = {
          box = false;
          frame = false;
        };
        pieChart.label = false;
      };
      remote = {
        widgets = [ ];
        widgetOrder = [
          "state"
          "label"
        ];
      };
      sensors = {
        enable = false;
        widgets = [ "label" ];
        widgetOrder = [
          "label"
          "mini"
          "sensors"
          "bar_chart"
        ];
      };
    };
  };
}
