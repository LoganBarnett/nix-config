################################################################################
# Self-hosted ntfy.sh push-notification server for the household, plus the
# nix-hapi-ntfy reconciler that provisions accounts and ACL grants from
# Nix.
#
# Why ntfy: docs/notifications.org.
# iOS notification-tier ceiling: docs/notifications.org § "iOS notification
# tier ceiling".
#
# Auth is deny-all.  The reconciler is the only mechanism that creates
# users; there is no out-of-band bootstrap.  If the reconciler is broken,
# fix the reconciler.
#
# Two users at first deploy:
#
# - admin:           human account for web-UI access; role=admin so a
#                    human can inspect/recover via the UI.
# - alertmanager:    service account for the alertmanager-ntfy adapter.
#                    role=user with write-only grants on alerts-page
#                    and alerts-info topics.
#
# Both passwords use mkManagedFromPath: agenix is the authoritative
# record, and any drift (someone changing a password via the UI) is
# reverted on the next reconcile.  The reconciler re-issues change-pass
# every run; plan output will show a Modify on each user's password
# until the live state can be diffed against the bcrypt hash, which
# the ntfy CLI does not expose.
#
# Topic split (alerts-page vs alerts-info) carries the urgency contract
# AlertManager will route on: alerts-page gets X-Priority: 5 (iOS
# time-sensitive, breaks default Focus modes); alerts-info gets
# X-Priority: 3 (normal delivery, silenced during Focus modes).
################################################################################
{
  config,
  facts,
  flake-inputs,
  pkgs,
  system,
  ...
}:
let
  inherit (flake-inputs.nix-hapi.lib) mkManagedFromPath;
  service-credentials = "/run/credentials/nix-hapi-ntfy.service";
in
{
  imports = [
    flake-inputs.nix-hapi-provider-ntfy.nixosModules.default
  ];
  networking.dnsAliases = [ "ntfy" ];
  services.https.fqdns."ntfy.${facts.network.domain}" = {
    # The module defaults listen-http to 127.0.0.1:2586; the reverse
    # proxy is the only external entry point.
    internalPort = 2586;
  };
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${facts.network.domain}";
      # Anonymous read/write is off; every publisher and subscriber must
      # authenticate.  The reconciler owns the user/ACL set.
      auth-default-access = "deny-all";
    };
  };

  # Account passwords.  agenix-rekey generates fresh random values into
  # the .age files when they're missing; both flow through systemd
  # LoadCredential into the reconciler's runtime credentials directory.
  age.secrets.ntfy-admin-password = {
    generator.script = "base64";
    rekeyFile = ../secrets/ntfy-admin-password.age;
  };
  age.secrets.ntfy-alertmanager-password = {
    generator.script = "base64";
    rekeyFile = ../secrets/ntfy-alertmanager-password.age;
  };

  services.nix-hapi.enable = true;
  services.nix-hapi-ntfy = {
    enable = true;
    # Threaded explicitly so nix-config-private's overridePkg substitution
    # (which patches the provider's Cargo git deps to gitea) is what
    # actually runs.  The module's own self.packages default would resolve
    # to the un-patched build whose Cargo.lock points nix-hapi-lib at
    # GitHub, unreachable from silicon's nix-daemon.
    package = flake-inputs.nix-hapi-provider-ntfy.packages.${system}.default;

    scopes.silicon = {
      provider = {
        # Full store path so the reconciler doesn't depend on systemd's
        # PATH including the ntfy binary.
        ntfyBin = "${pkgs.ntfy-sh}/bin/ntfy";
        serverConfig = "/etc/ntfy/server.yml";
      };
      users.admin = {
        role = "admin";
        password = mkManagedFromPath "${service-credentials}/ntfy-admin-password";
      };
      users.alertmanager = {
        role = "user";
        password = mkManagedFromPath "${service-credentials}/ntfy-alertmanager-password";
      };
      accesses.alertmanager-page = {
        user = "alertmanager";
        topic = "alerts-page";
        permission = "write-only";
      };
      accesses.alertmanager-info = {
        user = "alertmanager";
        topic = "alerts-info";
        permission = "write-only";
      };
    };
  };

  # Bind the agenix-decrypted passwords into the reconciler service's
  # credentials directory so the mkManagedFromPath / mkInitialFromPath
  # values resolve at run time.
  systemd.services.nix-hapi-ntfy.serviceConfig.LoadCredential = [
    "ntfy-admin-password:${config.age.secrets.ntfy-admin-password.path}"
    "ntfy-alertmanager-password:${config.age.secrets.ntfy-alertmanager-password.path}"
  ];

  # Goss health checks: external HTTPS reachability, loopback listener,
  # and service liveness.  ntfy.sh exposes a /v1/health endpoint that
  # returns 200 OK when the server is accepting requests.
  services.goss.checks = {
    http."https://ntfy.${facts.network.domain}/v1/health" = {
      status = 200;
      timeout = 5000;
    };
    port."tcp:2586" = {
      listening = true;
      ip = [ "127.0.0.1" ];
    };
    port."tcp:443" = {
      listening = true;
    };
    service.ntfy-sh = {
      enabled = true;
      running = true;
    };
    service.nix-hapi-ntfy = {
      enabled = true;
      # Oneshot — `running = false` once it's exited cleanly.
    };
  };
}
