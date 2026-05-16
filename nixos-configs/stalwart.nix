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

      # Smoke test: literal variable assignment + interpolation.
      set "literal" "ok";
      addheader "X-Probe-Literal" "''${literal}";

      # Envelope :matches with two-capture pattern.
      set "env_matched" "no";
      set "env_local" "(unset)";
      set "env_domain" "(unset)";
      if envelope :matches "to" "*@*" {
        set "env_matched" "yes";
        set "env_local" "''${1}";
        set "env_domain" "''${2}";
      }
      addheader "X-Probe-Env-Matched" "''${env_matched}";
      addheader "X-Probe-Env-Local" "''${env_local}";
      addheader "X-Probe-Env-Domain" "''${env_domain}";

      # Header :matches with two-capture pattern.
      set "hdr_matched" "no";
      set "hdr_local" "(unset)";
      set "hdr_domain" "(unset)";
      if header :matches "to" "*@*" {
        set "hdr_matched" "yes";
        set "hdr_local" "''${1}";
        set "hdr_domain" "''${2}";
      }
      addheader "X-Probe-Hdr-Matched" "''${hdr_matched}";
      addheader "X-Probe-Hdr-Local" "''${hdr_local}";
      addheader "X-Probe-Hdr-Domain" "''${hdr_domain}";

      addheader "X-Probe-Stage" "data";
    '';
    session.data.script = "'catch-all-probe'";
  };
}
