################################################################################
# Immich photo/video backup on silicon.  Media lives on the /tank/data LVM
# volume so the service must wait for that mount before starting.
################################################################################
{ config, facts, ... }:
let
  # JSON template for the Immich system config file (IMMICH_CONFIG_FILE).
  # The %..% placeholder is replaced at rekey time by the template-file
  # generator with the decrypted client secret.
  immichOauthConfigTemplate = builtins.toJSON {
    oauth = {
      enabled = true;
      issuerUrl = "https://authelia.${facts.network.domain}";
      clientId = "immich";
      clientSecret = "%immich-oidc-client-secret%";
      scope = "openid profile email groups";
      signingAlgorithm = "RS256";
      buttonText = "Login with SSO";
      autoRegister = true;
      autoLaunch = false;
      storageLabelClaim = "preferred_username";
      mobileOverrideEnabled = false;
    };
  };
in
{
  imports = [ ../nixos-modules/immich.nix ];
  networking.dnsAliases = [ "immich" ];
  # Immich 2.x receives no further upstream fixes and 3.x only lands in 26.11,
  # so CVE-2026-59258 and CVE-2026-82272 are knowingly carried until that
  # upgrade.  Revisit when the pinned nixpkgs can supply immich 3.x.
  nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ];

  age.secrets."immich-oauth-config" = {
    generator = {
      script = "template-file";
      dependencies = [ config.age.secrets."immich-oidc-client-secret" ];
    };
    settings.template = immichOauthConfigTemplate;
  };

  services.immich-host = {
    enable = true;
    mediaLocation = "/tank/data/immich";
    mountDependencies = [ "tank-data.mount" ];
    oauthConfigFile = config.age.secrets."immich-oauth-config".path;
  };

  # Immich does OIDC discovery against authelia.${domain} at startup, so gate
  # on oidc-ready.target (Authelia healthy) and nss-lookup.target (DNS for
  # authelia.${domain} resolves).
  systemd.services.immich-server = {
    after = [
      "oidc-ready.target"
      "nss-lookup.target"
    ];
    wants = [
      "oidc-ready.target"
      "nss-lookup.target"
    ];
  };
}
