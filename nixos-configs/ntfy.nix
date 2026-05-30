################################################################################
# Self-hosted ntfy.sh push-notification server for the household.
#
# Why ntfy: docs/notifications.org.
# iOS notification-tier ceiling: docs/notifications.org § "iOS notification
# tier ceiling".
#
# Auth is deny-all from day one.  No user is created here; the
# `services.nix-hapi-ntfy` reconciler (declared in nix-config-private)
# provisions every account and ACL grant.  No out-of-band bootstrap — if
# the reconciler is broken, fix the reconciler; do not add users by hand.
#
# The NixOS module generates the runtime config at /etc/ntfy/server.yml
# from `services.ntfy-sh.settings`; that is the path the reconciler reads
# to discover the auth-file location.
################################################################################
{
  config,
  facts,
  ...
}:
{
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
  };
}
