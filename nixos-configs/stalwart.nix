################################################################################
# Stalwart mail server configuration — the network-invariant pieces.
#
# Domain list, DKIM secrets, ACME certs, internal/external domain wiring, and
# catch-all routing all live in stalwart-facts.nix, sourced from
# facts.network.mail.  This file declares only:
#
#   - The stalwart LDAP service account (uniform across networks).
#   - The internalTls cert/key pair, named after the internal domain.
#   - services.stalwart-host.enable (the activation flip).
#
# Authentication is LDAP-backed against OpenLDAP on silicon.  ldap-auth.nix
# auto-emits the service account's password secrets.
#
# Before first deploy, generate all secrets:
#   agenix rekey generate --rekey -a
# Then commit the generated secrets/tls-mail.<internal-domain>.crt to the
# repository.
#
# After a DKIM secret is generated, extract the public key for the DNS TXT
# record at default._domainkey.<domain>:
#   openssl pkey -in <(rage --decrypt secrets/generated/stalwart-dkim-<domain>.age) \
#     -pubout | grep -v '^-----' | tr -d '\n'
################################################################################
{ facts, ... }:
{
  imports = [ ./stalwart-facts.nix ];

  # Register the stalwart LDAP service account.  ldap-auth.nix auto-emits:
  #   stalwart-ldap-password         — plaintext, delivered via LoadCredential
  #   stalwart-ldap-password-hashed  — argon2 hash for the LDAP reconciler
  auth.ldap.users.stalwart = {
    fullName = "Stalwart mail service account";
    type = "service";
    group = "stalwart-mail";
    managed = true;
  };

  services.stalwart-host = {
    enable = true;

    # TODO: this still bakes the internal domain into the secret filename.
    # Lift the rename when the internal domain isn't `proton`.
    internalTls = {
      certFile = "${../secrets/tls-mail.proton.crt}";
      keySecretName = "tls-mail.proton.key";
    };
  };

  # ── EXPERIMENT: custom spam-filter rules ───────────────────────────────
  # Test whether local TOML [spam-filter.rule.X] entries merge with the
  # bundled spam-filter.toml resource, and whether new tag scores in
  # [spam-filter.list].scores compose with the bundled scores.  If both
  # work, this is the production design path for catch-all sender
  # alignment policy.
  #
  # Aligned:    From: domain matches the recipient local part (or is a
  #             subdomain of it).  Mild confidence boost.
  # Mismatch:   Catch-all'd recipient + sender from an unrelated domain.
  #             Suspected leak — mild spam bump.
  #
  # Remove after the experiment, or generalize via stalwart-facts.nix.
  services.stalwart-mail.settings = {
    spam-filter.rule.STWT_CATCHALL_SENDER_ALIGNED = {
      enable = true;
      scope = "any";
      priority = 2000;
      condition = [
        {
          "if" =
            "to.domain == 'logustus.com' && (from.domain == to.local || ends_with(from.domain, '.' + to.local))";
          "then" = "'CATCHALL_SENDER_ALIGNED'";
        }
        { "else" = false; }
      ];
    };
    spam-filter.rule.STWT_CATCHALL_SENDER_MISMATCH = {
      enable = true;
      scope = "any";
      priority = 2001;
      condition = [
        {
          "if" =
            "to.domain == 'logustus.com' && from.domain != to.local && !ends_with(from.domain, '.' + to.local)";
          "then" = "'CATCHALL_SENDER_MISMATCH'";
        }
        { "else" = false; }
      ];
    };
    spam-filter.list.scores = {
      "CATCHALL_SENDER_ALIGNED" = "-1.5";
      "CATCHALL_SENDER_MISMATCH" = "1.0";
    };
  };
}
