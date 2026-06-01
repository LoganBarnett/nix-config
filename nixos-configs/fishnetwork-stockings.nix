################################################################################
# Connect to fishnetwork-stockings.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  psk-name = "wifi-psk";
  # This doesn't work, because a sub-unit is setup for the specific interface
  # that wpa_supplicant finds.  Unless we want to lock into specific interfaces
  # (we don't, lest this module become non-reusable), we need to rely on the
  # fact that this service must run as root to operate, and simply point it at
  # the agenix-located secret directly.
  # psk-path = "$CREDENTIALS_DIRECTORY/${psk-name}";
  psk-path = config.age.secrets.fishnetwork-stockings-5g-password.path;
  psk-script = pkgs.writeShellApplication {
    name = "psk-script";
    text = ''
      ${pkgs.coreutils}/bin/cat ${psk-path}
    '';
  };
  # The SSIDs this host joins, in priority order (higher = preferred).
  # Both the wpa_supplicant network list and the dhcpcd carrier-flap
  # hardening below derive from this — change here and both follow.
  ssids = [
    {
      name = "fishnetwork-stockings-5g";
      priority = 20;
    }
    {
      name = "fishnetwork-stockings";
      priority = 5;
    }
  ];
in
{
  age.secrets.fishnetwork-stockings-5g-password = {
    shared = true;
    rekeyFile = ../secrets/fishnetwork-stockings-5g-password.age;
  };
  age.secrets.fishnetwork-stockings-5g-password-environment-variable = {
    generator = {
      script = "environment-variable";
      dependencies = [
        config.age.secrets.fishnetwork-stockings-5g-password
      ];
    };
    settings.field = "psk_fishnetwork_stockings";
  };
  networking.wireless = {
    enable = true;
    # If we need more than one later, we'll need to combine them into a proper
    # "environment file".
    secretsFile =
      config.age.secrets.fishnetwork-stockings-5g-password-environment-variable.path;
    networks = lib.listToAttrs (
      map (s: {
        inherit (s) name;
        value = {
          inherit (s) priority;
          pskRaw = "ext:psk_fishnetwork_stockings";
        };
      }) ssids
    );
  };
  # WiFi roams between APs trigger dhcpcd's carrier-loss handler, which
  # tears down the address and routes.  If the rebind on reassociation
  # doesn't confirm the lease within ~5s — common when the new AP's
  # bridge is still learning MACs or running STP — dhcpcd falls back to
  # IPv4LL (169.254.x) and the host is stranded until something else
  # provokes a fresh DHCP cycle.  These per-SSID overrides keep dhcpcd
  # patient on the WiFi path; an Ethernet interface on the same host
  # still gets the vanilla defaults.
  networking.dhcpcd.extraConfig = lib.concatMapStrings (s: ''
    ssid ${s.name}
      # Never fall back to IPv4LL.  Just keep retrying DHCP.
      nohook ipv4ll
      # Reuse the existing lease for up to 30s after carrier returns,
      # giving the AP's bridge time to learn our MAC.
      reboot 30

  '') ssids;
  # wpa_supplicant spawns off a sub-service of sorts.  Using the @ notation
  # below, we can indicate these settings apply to any of the sub-services (and
  # perhaps the primary service itself, but I have not verified this).
  systemd.services."wpa_supplicant@" =
    let
      after = [ "run-agenix.d.mount" ];
    in
    {
      inherit after;
      requires = after;
      # This doesn't work, because a sub-unit is setup for the specific interface
      # that wpa_supplicant finds.  Unless we want to lock into specific
      # interfaces (we don't, lest this module become non-reusable), we need to
      # rely on the fact that this service must run as root to operate, and simply
      # point it at the agenix-located secret directly.
      serviceConfig.LoadCredential = [
        "${psk-name}:${config.age.secrets.fishnetwork-stockings-5g-password.path}"
      ];
    };
}
