################################################################################
# ncps: a pull-through cache in front of cache.nixos.org.
#
# Attic (./attic.nix) only holds what is pushed to it, so upstream paths need a
# second store.  ncps fetches a path from cache.nixos.org on the first miss,
# keeps it under /tank, and serves it from then on.  Signatures pass through
# unchanged, so consumers keep trusting cache.nixos.org-1 and no new key is
# involved.  Its nix-cache-info advertises priority 10, which is why the attic
# cache is created with a lower number (see facts.network.binaryCache).
################################################################################
{ facts, ... }:
let
  inherit (facts.network) binaryCache domain;
  fqdn = "${binaryCache.ncpsAlias}.${domain}";
  port = 8501;
  dataDir = "/tank/data/ncps/data";
in
{
  services.ncps = {
    enable = true;
    # Usage statistics phone home by default.
    analytics.reporting.enable = false;
    prometheus.enable = true;
    # Bound on every interface so the Prometheus server scrapes it as
    # silicon:8501 over the loopback route.  The firewall stays closed to the
    # LAN, which reaches it through nginx only.
    server.addr = ":${toString port}";
    cache = {
      hostName = fqdn;
      # Subdirectories of data/, because tank-volumes owns data/ itself and the
      # ncps module declares its own tmpfiles rules for these paths.
      storage.local = "${dataDir}/local";
      # Whole NARs are downloaded here before serving; keep that off the root
      # disk.
      tempPath = "${dataDir}/tmp";
      maxSize = "500G";
      lru.schedule = "0 3 * * *";
      signNarinfo = false;
      upstream = {
        urls = [ "https://cache.nixos.org" ];
        publicKeys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        ];
        dialerTimeout = "5s";
      };
    };
  };

  # Derived data; nothing here is worth backing up.
  tankVolumes.volumes.ncps = {
    group = "ncps";
    backupData = false;
  };

  networking.dnsAliases = [ binaryCache.ncpsAlias ];
  networking.monitors = [ "ncps" ];
  services.https.fqdns.${fqdn}.internalPort = port;
  # A first fetch of a large NAR takes a while; stream it rather than buffer.
  services.nginx.virtualHosts.${fqdn}.locations."/".extraConfig = ''
    proxy_buffering off;
    proxy_read_timeout 600s;
  '';

  services.goss.checks = {
    http."https://${fqdn}/nix-cache-info" = {
      status = 200;
      timeout = 3000;
    };
    # Go binds ":port" dual-stack, which shows up as an IPv6 listener.
    port."tcp6:${toString port}" = {
      listening = true;
    };
    service.ncps = {
      enabled = true;
      running = true;
    };
  };
}
