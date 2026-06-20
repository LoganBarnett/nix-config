################################################################################
# Sytter is an IFTTT platform for a host.  Use it to do things such as ensure
# BlueTooth is disabled when the machine goes to sleep.
################################################################################
{
  facts,
  flake-inputs,
  pkgs,
  ...
}:
let
  macos-keyboard-remap =
    pkgs.callPackage ../packages/macos-keyboard-remap.nix
      { };
  vpn-reconcile = pkgs.callPackage ../packages/vpn-reconcile.nix {
    inherit facts;
  };
  # vpn-reconcile must run as root (wg-quick, route).  Sytter runs as an
  # unprivileged user agent, so the sytt below invokes it through a scoped
  # NOPASSWD sudo rule (declared in security.sudo.extraConfig).  When sytter
  # grows a root-daemon mode, move this sytt there and drop the sudo rule.
  reconcile-cmd = "/usr/bin/sudo ${vpn-reconcile}/bin/vpn-reconcile";
in
{
  imports = [
    ../nixos-modules/lib-custom.nix
    flake-inputs.sytter.darwinModules.default
  ];
  nixpkgs.overlays = [
    flake-inputs.sytter.overlays.default
  ];
  # vpn-reconcile on PATH so it can be run by hand.
  environment.systemPackages = [ vpn-reconcile ];
  # Scoped passwordless privilege; sytter's user agent runs as `logan`.  The
  # rule blesses the exact store path — see docs/nix-sudo-store-paths.org for
  # why store paths over the /run/current-system/sw/bin symlink.
  security.sudo.extraConfig = ''
    logan ALL=(root) NOPASSWD: ${vpn-reconcile}/bin/vpn-reconcile
  '';
  services.sytter = {
    enable = true;
    sytters = {
      keyboard-remap = {
        name = "macOS keyboard remap";
        description = "Apply key remapping when any device connects.";
        triggers = [
          {
            kind = "device-connection";
            events = [ "Add" ];
            device_types = [ "any" ];
          }
        ];
        executors = [
          {
            kind = "shell";
            script = "${macos-keyboard-remap}/bin/macos-keyboard-remap";
          }
        ];
      };
      vpn-reconcile = {
        name = "Always-on VPN reconciler";
        description = ''
          Keep the WireGuard tunnel in the right state as the laptop roams:
          down at home (direct LAN), split-tunnel while roaming, full-tunnel in
          travel mode.  The reconciler is level-triggered and idempotent, so the
          cron tick is the correctness floor and the Wake / network-device
          events just make it responsive.
        '';
        triggers = [
          # Correctness floor: catches everything the events below miss
          # (e.g. roaming between Wi-Fi networks while awake).
          {
            kind = "cron";
            cron = "0 * * * * *";
          }
          # Lid-open recovery: the tunnel is often dead after wake.
          {
            kind = "power";
            events = [ "Wake" ];
          }
          # Tether / dongle plug-in: a new network interface appears.
          {
            kind = "device-connection";
            events = [ "Add" ];
            device_types = [ "network" ];
          }
        ];
        executors = [
          {
            kind = "shell";
            script = reconcile-cmd;
          }
        ];
      };
    };
  };
}
