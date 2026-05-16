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

  # ── EXPERIMENT: sieve probe ────────────────────────────────────────────
  # Temporary diagnostic to answer:
  #   1. Whether [sieve.trusted.scripts.X] in local TOML is honored in 0.14.
  #   2. Whether `envelope :matches "to"` at the DATA stage sees the
  #      pre-rewrite or post-rewrite recipient.
  #   3. Where our header insertions land relative to X-Spam-* headers
  #      (which tells us classifier ordering vs our script).
  #
  # Remove after the experiment is concluded.
  services.stalwart-mail.settings = {
    sieve.trusted.scripts.catch-all-probe.contents = ''
      require ["editheader", "envelope", "variables"];

      if envelope :matches "to" "*" {
        set "env_to" "''${1}";
      } else {
        set "env_to" "(none)";
      }

      if header :matches "to" "*" {
        set "hdr_to" "''${1}";
      } else {
        set "hdr_to" "(none)";
      }

      addheader "X-Probe-Envelope-To" "''${env_to}";
      addheader "X-Probe-Header-To" "''${hdr_to}";
      addheader "X-Probe-Stage" "data";
    '';
    session.data.script = "'catch-all-probe'";
  };
}
