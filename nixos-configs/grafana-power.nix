################################################################################
# Power - Grafana dashboard.
#
# Skeleton for the IoTaWatt whole-house power monitor.  The IoTaWatt to
# InfluxDB pipeline does not exist yet, so each section is a text placeholder
# describing the panels that will live there; the dashboard must render
# cleanly with no datasource configured.  See docs/power-monitoring.org in the
# private repo for the full design.
################################################################################
{ ... }:
{
  id = null;
  uid = "power";
  schemaVersion = 38;
  title = "Power";
  panels = [
    {
      type = "text";
      title = "Live Power";
      gridPos = {
        h = 8;
        w = 24;
        x = 0;
        y = 0;
      };
      options = {
        mode = "markdown";
        content = ''
          ## Live Power

          Planned panels: watts per labeled circuit (stacked area plus
          per-circuit series), total household draw, and heat pump amps.

          Awaiting the IoTaWatt to InfluxDB data pipeline.
        '';
      };
    }
    {
      type = "text";
      title = "Billing Cycle";
      gridPos = {
        h = 8;
        w = 24;
        x = 0;
        y = 8;
      };
      options = {
        mode = "markdown";
        content = ''
          ## Billing Cycle

          Planned panels: cumulative kWh since the billing cycle start and a
          running cost estimate from the utility rate, with the cycle start
          day as a dashboard variable.

          Awaiting the IoTaWatt to InfluxDB data pipeline.
        '';
      };
    }
    {
      type = "text";
      title = "Heat Pump Diagnostics";
      gridPos = {
        h = 8;
        w = 24;
        x = 0;
        y = 16;
      };
      options = {
        mode = "markdown";
        content = ''
          ## Heat Pump Diagnostics

          Planned panels: leg A volts, leg B volts, line-to-line volts, amps,
          and watts at full five second resolution, plus alerting on
          sustained per-leg voltage excursions.

          Awaiting the IoTaWatt to InfluxDB data pipeline.
        '';
      };
    }
  ];
}
