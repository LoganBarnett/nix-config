################################################################################
# Maps facts.network.mail data into services.stalwart-mail.settings and
# related declarations.
#
# Data shape (facts.network.mail.externalDomains): attrset keyed by domain
# name.  Each entry declares its DKIM selector + secret name and optionally
# names a `catchAllUser` (a facts.network.users attribute key) whose derived
# primary address receives unmatched mail for the domain.
#
# This file emits, per external domain:
#   - DKIM signing config and the corresponding age secret
#   - Per-domain Stalwart TOML certificate entry
#   - ACME cert managed under security.acme.certs
#   - LoadCredential entries for the DKIM key and the ACME private key
#
# Globally:
#   - server.tls.certificate list (external domains + "internal" fallback)
#   - session.rcpt.rewrite expression with catch-all + auto-generated
#     exclusions for explicit LDAP `mail` values within catch-all'd domains
#   - extraSpamFilterRules and extraSpamFilterScores for sender-alignment
#     scoring on catch-all'd domains
#
# The "invariant" Stalwart wiring (listeners, storage, directory, service
# account) lives in the sibling stalwart.nix.
################################################################################
{
  config,
  facts,
  lib,
  ...
}:
let
  externalDomains = facts.network.mail.externalDomains;
  externalDomainNames = lib.attrNames externalDomains;

  # Resolve a facts.network.users attribute key to that user's derived
  # primary email address on the internal domain.  Matches the rule
  # applied by openldap-facts.nix when rendering the LDAP `mail`
  # attribute.
  userPrimary =
    name:
    let
      user = facts.network.users.${name};
      localPart = user.email.username or name;
    in
    "${localPart}@${facts.network.domain}";

  # All `mail` LDAP values across all email-enabled users.  Used to
  # auto-generate pass-through clauses in session.rcpt.rewrite — every
  # explicit address inside a catch-all'd domain must bypass the
  # catch-all so it routes to its actual owner.
  allMail = lib.lists.concatMap (
    user:
    lib.lists.optionals user.email.enable (
      [ "${user.email.username}@${facts.network.domain}" ] ++ user.email.aliases
    )
  ) (lib.attrValues config.auth.ldap.users);

  protectedFor =
    domain: lib.lists.filter (a: lib.strings.hasSuffix "@${domain}" a) allMail;

  catchAllDomainNames = lib.attrNames (
    lib.filterAttrs (_: cfg: cfg.catchAllUser != null) externalDomains
  );

  mkAlignmentRule = domain: {
    "STWT_CATCHALL_SENDER_ALIGNED_${
      lib.toUpper (lib.replaceStrings [ "." ] [ "_" ] domain)
    }" =
      {
        enable = true;
        scope = "any";
        priority = 2000;
        condition = [
          {
            "if" =
              "to.domain == '${domain}' && (from.domain == to.local || ends_with(from.domain, '.' + to.local))";
            "then" = "'CATCHALL_SENDER_ALIGNED'";
          }
          { "else" = false; }
        ];
      };
    "STWT_CATCHALL_SENDER_MISMATCH_${
      lib.toUpper (lib.replaceStrings [ "." ] [ "_" ] domain)
    }" =
      {
        enable = true;
        scope = "any";
        priority = 2001;
        condition = [
          {
            "if" =
              "to.domain == '${domain}' && from.domain != to.local && !ends_with(from.domain, '.' + to.local)";
            "then" = "'CATCHALL_SENDER_MISMATCH'";
          }
          { "else" = false; }
        ];
      };
  };
in
{
  # Catch errors at eval time instead of at run time when a bad string
  # would silently route nowhere.
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

  # Let's Encrypt certificate per external domain.  dnsProvider and
  # credentialsFiles inherit from security.acme.defaults (configured in
  # acme.nix).  Stalwart uses SNI to pick the right cert, so the cert
  # name must match the domain exactly.
  security.acme.certs = lib.mapAttrs (_: _: {
    group = "stalwart-mail";
    postRun = "systemctl reload-or-restart stalwart-mail.service || true";
  }) externalDomains;

  services.stalwart-mail.settings = {
    # The SNI cert list.  External domain certs first, then the internal
    # fallback for mail.<internal-domain> connections.  Stalwart matches
    # by hostname against names in the [certificate] section.
    server.tls.certificate = externalDomainNames ++ [ "internal" ];

    # Per-external-domain TLS certificate entries pointing at ACME paths.
    # fullchain.pem is world-readable; key.pem is delivered via
    # LoadCredential so no group-membership changes are needed.
    certificate = lib.mapAttrs (domain: _: {
      cert = "/var/lib/acme/${domain}/fullchain.pem";
      private-key = "%{file:/run/credentials/stalwart-mail.service/acme-key-${domain}}%";
    }) externalDomains;

    # DKIM signing config per external domain.
    auth.dkim.sign = lib.mapAttrs (domain: cfg: {
      algo = "ed25519-sha256";
      inherit domain;
      selector = cfg.dkimSelector;
      private-key = "%{file:/run/credentials/stalwart-mail.service/${cfg.dkimSecretName}}%";
      headers.relaxed = [
        "From"
        "To"
        "Message-ID"
        "Date"
        "Subject"
        "MIME-Version"
      ];
      canonicalization = "relaxed/relaxed";
    }) externalDomains;

    # Per-domain catch-all routing with auto-generated exclusions.
    #
    # For each externalDomain with a catchAllUser, rewrite *@domain
    # envelope recipients to the user's derived primary before LDAP
    # verify runs.  Explicit recipients — any address that some LDAP
    # user already claims via their derived primary or `email.aliases`
    # — are emitted as pass-through clauses *before* the regex
    # catch-all, so first-match-wins evaluation preserves them.
    #
    # Adding `email.aliases = [ "foo@logustus.com" ]` on any user
    # therefore automatically protects `foo@logustus.com` from the
    # catch-all without manual maintenance.
    session.rcpt.rewrite =
      lib.lists.concatMap (
        domain:
        let
          cfg = externalDomains.${domain};
          protected = protectedFor domain;
        in
        (map (a: {
          "if" = "rcpt == '${a}'";
          "then" = "rcpt";
        }) protected)
        ++ lib.optional (cfg.catchAllUser != null) {
          "if" = "matches('^.+@${lib.escapeRegex domain}$', rcpt)";
          "then" = "'${userPrimary cfg.catchAllUser}'";
        }
      ) externalDomainNames
      ++ [ { "else" = false; } ];
  };

  # Per-domain LoadCredential extensions: DKIM private key + ACME private
  # key.  Merges with the base set declared in stalwart.nix.
  systemd.services.stalwart-mail.serviceConfig.LoadCredential =
    lib.lists.concatMap
      (domain: [
        "${externalDomains.${domain}.dkimSecretName}:${
          config.age.secrets.${externalDomains.${domain}.dkimSecretName}.path
        }"
        "acme-key-${domain}:/var/lib/acme/${domain}/key.pem"
      ])
      externalDomainNames;

  # TODO: re-introduce sender-alignment scoring on catch-all'd domains
  # once the spam-filter merge in nixos-modules/stalwart.nix is working.
  # The mkAlignmentRule helper above generates the right schema; we just
  # can't wire it through extraSpamFilterRules / extraSpamFilterScores
  # until the bundled-TOML invalid-syntax problem is resolved.  Tracked
  # at https://github.com/LoganBarnett/stalwart-spam-filter-toml-bug.
}
