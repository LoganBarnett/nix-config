################################################################################
# Maps facts.network.mail data into the services.stalwart-host module config.
#
# The data shape (facts.network.mail.externalDomains) describes the domains
# this Stalwart instance authoritatively serves outside the internal network
# domain.  Per-domain entries optionally name a `catchAllUser` whose derived
# primary address receives all otherwise-unmatched mail at that domain.
#
# This file emits:
#   - services.stalwart-host.{internalDomain,externalDomains,ldap}
#   - age.secrets.<dkimSecretName>      (one per external domain)
#   - security.acme.certs.<domain>      (one per external domain)
#
# Anything not derivable from facts — service account decl, internalTls, the
# module enable — stays in the sibling stalwart.nix.
################################################################################
{
  facts,
  lib,
  ...
}:
let
  externalDomains = facts.network.mail.externalDomains;

  # Resolve a facts.network.users attribute key to that user's derived
  # primary email address on the internal domain.  Matches the rule applied
  # by openldap-facts.nix when rendering the LDAP `mail` attribute.
  userPrimary =
    name:
    let
      user = facts.network.users.${name};
      localPart = user.email.username or name;
    in
    "${localPart}@${facts.network.domain}";
in
{
  # Every catchAllUser must reference a real facts.nix user; misspellings
  # would silently fall back to a meaningless `${badName}@${domain}` rewrite
  # target if we resolved them unconditionally.
  assertions = lib.mapAttrsToList (domain: cfg: {
    assertion =
      cfg.catchAllUser == null || facts.network.users ? ${cfg.catchAllUser};
    message = ''
      facts.network.mail.externalDomains."${domain}".catchAllUser references
      unknown user "${toString cfg.catchAllUser}".  Add the user to
      facts.network.users or null out catchAllUser.
    '';
  }) externalDomains;

  age.secrets = lib.mapAttrs' (
    _: cfg:
    lib.nameValuePair cfg.dkimSecretName {
      generator.script = "stalwart-dkim-key";
    }
  ) externalDomains;

  services.stalwart-host = {
    internalDomain = facts.network.domain;

    externalDomains = lib.mapAttrsToList (domain: cfg: {
      inherit domain;
      inherit (cfg) dkimSelector dkimSecretName;
      catchAllTarget = lib.mapNullable userPrimary cfg.catchAllUser;
    }) externalDomains;

    ldap = {
      url = "ldaps://ldap.${facts.network.domain}:636";
      baseDn = "dc=${facts.network.domain},dc=org";
    };
  };

  # Let's Encrypt certificate per external domain.  dnsProvider and
  # credentialsFiles inherit from security.acme.defaults (configured in
  # acme.nix).  Stalwart uses SNI to pick the right cert, so the cert name
  # must match the domain exactly.
  security.acme.certs = lib.mapAttrs (_: _: {
    group = "stalwart-mail";
    postRun = "systemctl reload-or-restart stalwart-mail.service || true";
  }) externalDomains;
}
