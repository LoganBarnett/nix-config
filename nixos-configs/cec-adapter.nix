################################################################################
# Support for USB HDMI-CEC adapters (e.g. Pulse-Eight).
#
# Kodi's libcec talks directly to the Pulse-Eight adapter over the USB serial
# device (/dev/ttyACM0) using its P8_USB protocol.  This is simpler and
# better-supported than the kernel CEC framework path (inputattach → serio →
# pulse8_cec → /dev/cec0), which conflicts with libcec's exclusive serial
# access.
#
# The kernel CEC subsystem is still enabled for the i915 DRM driver, but the
# pulse8_cec module and inputattach service are intentionally omitted.
#
# HDMI port number: the adapter cannot auto-detect the physical TV port.
# The port is declaratively set via services.kodi-standalone.peripheralSettings
# below (defaulting to port 1).  Override cec_hdmi_port in the host config
# to match the actual TV HDMI input.
################################################################################
{
  lib,
  pkgs,
  ...
}:
let
  cecDefaults = lib.mapAttrs (_: lib.mkDefault) {
    activate_source = "1";
    button_release_delay_ms = "0";
    button_repeat_rate_ms = "0";
    cec_hdmi_port = "1";
    cec_standby_screensaver = "0";
    cec_wake_screensaver = "1";
    connected_device = "36037";
    device_name = "Kodi";
    device_type = "36051";
    double_tap_timeout_ms = "300";
    enabled = "1";
    pause_or_stop_playback_on_deactivate = "36045";
    pause_playback_on_deactivate = "0";
    physical_address = "ffff";
    power_avr_on_as = "0";
    # Kodi's defaults treat "Kodi is exiting" as "the viewer is done for the
    # night" and tell the TV so.  On a box where kodi.service has
    # Restart=always — and where an operator or a watchdog may restart it to
    # clear a wedged audio engine — that is wrong: every restart blanks the
    # TV out from under whoever is watching.  Both of these are Kodi
    # localisation string IDs used as enum values; see
    # share/kodi/system/peripherals.xml in the Kodi package for the accepted
    # sets.
    #
    # send_inactive_source: 0 stops the "Inactive source" command on shutdown,
    # which is what makes the TV switch away from this input.
    send_inactive_source = "0";
    # standby_devices: 231 is #231, "None".  The default 36037 is "TV", i.e.
    # power the TV off during shutdown.
    standby_devices = "231";
    standby_devices_advanced = "";
    # standby_pc_on_tv_standby: 36028 is #36028, "Ignore".  The default 13011
    # is #13011, "Suspend" — the TV going into standby would suspend the whole
    # host.  This has never fired here, but it is a live trapdoor on a media
    # box that is meant to stay up and serve its web interface.
    standby_pc_on_tv_standby = "36028";
    standby_tv_on_pc_standby = "1";
    tv_vendor = "0";
    use_tv_menu_language = "1";
    wake_devices = "36037";
    wake_devices_advanced = "";
  };
in
{
  environment.systemPackages = [
    # cec-client — interactive CEC console and scanner.
    pkgs.libcec
    # cec-ctl — low-level CEC monitoring and control.
    pkgs.v4l-utils
  ];

  # /dev/ttyACM0 is owned by root:dialout.  The kodi user needs this group
  # to open the serial device.
  users.groups.dialout = { };

  # Declarative CEC adapter settings.  Both files are managed because Kodi
  # reads one keyed by USB VID:PID and one generic CEC fallback.
  services.kodi-standalone.peripheralSettings = {
    "usb_2548_1002_CEC_Adapter" = cecDefaults;
    "cec_CEC_Adapter" = cecDefaults;
  };
}
