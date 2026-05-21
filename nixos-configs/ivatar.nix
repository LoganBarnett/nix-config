################################################################################
# ivatar Libravatar-compatible avatar service on silicon.
################################################################################
{ config, facts, ... }:
{
  services.ivatar-host = {
    enable = true;
    fqdn = "ivatar.${facts.network.domain}";
    oidc.enable = true;
  };

  services.https.fqdns."ivatar.${facts.network.domain}" = {
    internalPort = config.services.ivatar-host.port;
  };

  # OIDC client of authelia.${domain} -- gate startup on the auth provider
  # being healthy and DNS being able to resolve it.
  systemd.services.ivatar = {
    after = [
      "run-agenix.d.mount"
      "oidc-ready.target"
      "nss-lookup.target"
    ];
    requires = [ "run-agenix.d.mount" ];
    wants = [
      "oidc-ready.target"
      "nss-lookup.target"
    ];
  };
}
