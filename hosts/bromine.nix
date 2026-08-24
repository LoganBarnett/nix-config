################################################################################
# Bromine is a trace element that is highly reactive and thus isn't found freely
# in nature.  It was used long ago as a sedative and can help people with
# epilepsy.
################################################################################
{
  facts,
  flake-inputs,
  host-id,
  system,
  ...
}:
let
  grafana-url =
    uid:
    "https://grafana.${facts.network.domain}/d/${uid}/${uid}"
    + "?orgId=1&from=now-6h&to=now&timezone=America/Los_Angeles"
    + "&kiosk=fullscreen&refresh=1m";
in
{
  imports = [
    ../nixos-configs/raspberry-pi-usb-disk.nix
    ../nixos-configs/raspberry-pi-4.nix
    ../nixos-modules/grafana-kiosk.nix
    ../nixos-modules/linux-host.nix
    # ../nixos-configs/home-assistant.nix
    # ../nixos-configs/mosquitto.nix
    # ../nixos-configs/openhab.nix
    # ../nixos-configs/zwave-js-server.nix
    # ../nixos-configs/zwave-js-ui.nix
    # ../nixos-configs/matrix-signal-bridge.nix
    {
      networking.hostId = "37fab2ca";
      nixpkgs.hostPlatform = system;
    }
  ];
  # Brightness is deliberately left unset on both displays.  A previous
  # attempt to brighten the panel (xrandr --brightness 2.0) targeted eDP-1,
  # an output that does not exist on a Pi, so it never applied and the panels
  # have always run at 1.0.  Software brightness above 1.0 clips highlights;
  # tune live first (e.g. sudo --user=kiosk DISPLAY=:0 xrandr --output HDMI-1
  # --brightness 1.3) and set the displays.<output>.brightness option once a
  # value is proven out.
  services.grafana-kiosk = {
    enable = true;
    displays = {
      "HDMI-1" = {
        url = grafana-url "system-monitoring";
        width = 1920;
        height = 1080;
        primary = true;
      };
      "HDMI-2" = {
        url = grafana-url "power";
        width = 1280;
        height = 1024;
        x = 1920;
      };
    };
  };
  networking.monitors = [ "goss" ];
}
