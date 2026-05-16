################################################################################
# Stalwart mail server — the network-invariant pieces.
#
# Anything network-specific (which external domains we own, which user is
# the catch-all target, DKIM secret names, ACME certs, the rewrite rules)
# lives in stalwart-facts.nix, sourced from facts.network.mail.  This file
# handles:
#
#   - The stalwart LDAP service account.
#   - services.stalwart-mail enablement and base settings (storage,
#     directory, listeners, server hostname, internal cert, relay rule).
#   - systemd unit extensions (credential strip, LoadCredential basics).
#   - Tank-volume + firewall ports.
#
# Listener layout (port: protocol / TLS mode / purpose):
#   25   SMTP  STARTTLS   Inbound MX
#   587  SMTP  STARTTLS   Authenticated client submission
#   993  IMAP  implicit   Mailbox access
################################################################################
{
  config,
  facts,
  pkgs,
  ...
}:
let
  domain = facts.network.domain;
  baseDn = "dc=${domain},dc=org";
  internalFqdn = "mail.${domain}";

  serviceAccount = "stalwart";
  ldapCredential = "${serviceAccount}-ldap-password";

  # Stalwart's %{file:...}% macro reads files verbatim, including trailing
  # newlines.  agenix-decrypted secrets end with \n, which makes the LDAP
  # bind password wrong.  ExecStartPre strips the newline into this path.
  strippedCredsDir = "/run/stalwart-mail-creds";
  strippedLdapCred = "${strippedCredsDir}/${ldapCredential}";

  internalKeySecret = "tls-mail.${domain}.key";
  internalCertFile = "${../secrets/tls-mail.${domain}.crt}";
in
{
  imports = [ ./stalwart-facts.nix ];

  networking.dnsAliases = [ "mail" ];

  # Internal TLS leaf cert for mail.<internal-domain>.  agenix-rekey
  # generates secrets/tls-mail.<domain>.key.age and the plain .crt file.
  tls.tls-leafs.${internalFqdn} = {
    fqdn = internalFqdn;
    ca = config.age.secrets.proton-ca;
  };

  # LDAP service account.  ldap-auth.nix auto-emits its plaintext and
  # hashed password secrets given this declaration.
  auth.ldap.users.${serviceAccount} = {
    fullName = "Stalwart mail service account";
    type = "service";
    group = "stalwart-mail";
    managed = true;
  };

  services.stalwart-mail = {
    enable = true;
    settings = {
      # All data backed by a single embedded RocksDB instance.  Migrate to
      # PostgreSQL later if needed.
      storage = {
        data = "rocksdb";
        blob = "rocksdb";
        fts = "rocksdb";
        lookup = "rocksdb";
        directory = "ldap";
      };

      store.rocksdb = {
        type = "rocksdb";
        path = "/tank/data/stalwart-mail/data";
        compression = "lz4";
      };

      # LDAP directory for user authentication and address lookup.  Users
      # bind with their own credentials via the re-bind flow; the service
      # account is used only for lookups.
      directory.ldap = {
        type = "ldap";
        url = "ldaps://ldap.${domain}:636";
        base-dn = baseDn;
        # Stalwart uses rustls with webpki-roots, which ignores the system
        # trust store.  The internal CA is not in Mozilla's root list, so
        # we must skip verification here.
        tls.allow-invalid-certs = true;
        bind = {
          dn = "uid=${serviceAccount},ou=users,${baseDn}";
          # %{file:...}% reads the credential at runtime so the password
          # never appears in the Nix store.  We use the stripped copy (no
          # trailing newline) from ExecStartPre.
          secret = "%{file:${strippedLdapCred}}%";
          # LDAP bind auth: Stalwart looks up the user's DN, then binds
          # as that user with the provided password.  This lets OpenLDAP
          # verify argon2 hashes natively instead of Stalwart trying (and
          # failing) to verify them locally.
          auth.method = "lookup";
        };
        filter = {
          name = "(&(objectClass=inetOrgPerson)(uid=?))";
          email = "(&(objectClass=inetOrgPerson)(mail=?))";
          verify = "(&(objectClass=inetOrgPerson)(mail=?))";
          expand = "";
          # `?` is substituted with the domain being checked.  Match any
          # user with a `mail` attribute at that domain (including the
          # empty-local-part `@<domain>` catch-all aliases).
          domains = "(&(objectClass=inetOrgPerson)(mail=*@?))";
        };
        attributes = {
          name = "uid";
          description = [ "cn" ];
          email = [ "mail" ];
          member-of = [ "memberOf" ];
        };
      };

      server = {
        hostname = internalFqdn;

        listener.smtp = {
          bind = [ "0.0.0.0:25" ];
          protocol = "smtp";
          tls.implicit = false;
        };

        listener.submission = {
          bind = [ "0.0.0.0:587" ];
          protocol = "smtp";
          tls.implicit = false;
        };

        listener.imaps = {
          bind = [ "0.0.0.0:993" ];
          protocol = "imap";
          tls.implicit = true;
        };

        # Stalwart's HTTP management API, exposed on loopback only.  Used
        # for `stalwart-cli` diagnostics; not reachable from the LAN.
        # Port 8087 chosen to avoid collisions with nginx (8080) and
        # other services on the host.
        listener.http = {
          bind = [ "127.0.0.1:8087" ];
          protocol = "http";
          tls.implicit = false;
        };

        tls = {
          enable = true;
          implicit = false;
          # The full cert list is composed by stalwart-facts.nix, which
          # knows the external domains.  This file contributes "internal";
          # module merging takes care of combining them.
        };
      };

      certificate.internal = {
        cert = "%{file:${internalCertFile}}%";
        private-key = "%{file:/run/credentials/stalwart-mail.service/tls-key}%";
      };

      # Allow relay only for authenticated users.
      session.rcpt.relay = [
        {
          "if" = "!is_empty(authenticated_as)";
          "then" = true;
        }
        { "else" = false; }
      ];
    };
  };

  systemd.services.stalwart-mail = {
    # Restart whenever the generated TOML changes (relay rules, cert
    # paths, LDAP filters, etc.).  The upstream module does not trigger
    # restarts on settings changes by itself.
    restartTriggers = [ (builtins.toJSON config.services.stalwart-mail.settings) ];
    after = [
      "ldap-reconciler.service"
      "run-agenix.d.mount"
      "tank-data.mount"
    ];
    wants = [ "ldap-reconciler.service" ];
    requires = [
      "run-agenix.d.mount"
      "tank-data.mount"
    ];
    serviceConfig = {
      # ProtectSystem=strict (set by the upstream module) makes the
      # filesystem read-only.  The tank RocksDB path is outside the
      # StateDirectory so it needs an explicit exemption.
      ReadWritePaths = [ "/tank/data/stalwart-mail" ];
      RuntimeDirectory = "stalwart-mail-creds";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = [
        "+${pkgs.writeShellScript "stalwart-strip-creds" ''
          # Stalwart's %{file:...}% reads verbatim, so strip trailing
          # newlines that agenix adds to secret files.
          ${pkgs.coreutils}/bin/tr -d '\n' \
            < /run/credentials/stalwart-mail.service/${ldapCredential} \
            > ${strippedLdapCred}
          chown stalwart-mail:stalwart-mail ${strippedLdapCred}
          chmod 0400 ${strippedLdapCred}
        ''}"
      ];
      LoadCredential = [
        "${ldapCredential}:${config.age.secrets.${ldapCredential}.path}"
        "tls-key:${config.age.secrets.${internalKeySecret}.path}"
      ];
    };
  };

  # Mail data lives on the tank volume so it participates in the existing
  # btrfs + restic backup pipeline.  No quiesce needed — RocksDB's WAL
  # ensures every btrfs snapshot of a live instance is recoverable.
  # group = "stalwart-mail" makes tmpfiles create the tank directory with
  # the right ownership so the service user can write to the RocksDB path.
  tankVolumes.volumes.stalwart-mail = {
    backupData = true;
    group = "stalwart-mail";
  };

  networking.firewall.allowedTCPPorts = [
    25
    587
    993
  ];
}
