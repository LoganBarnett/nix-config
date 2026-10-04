################################################################################
# Attic binary cache server: the LAN store for everything built here.
#
# Two units wrap the stock atticd module.  attic-cache-ensure creates the cache
# on first start with the agenix-managed signing keypair, so consumers trust a
# public key that lives in this repository and the cache can be recreated
# (database loss, migration) without touching any client.  attic-watch-store
# pushes every store path silicon registers; paths signed by cache.nixos.org are
# skipped because ncps (./ncps.nix) fronts upstream.
#
# This is ensure-only.  Renames, removal, retention or priority drift, and
# tokens for other hosts belong to a nix-hapi-provider-attic reconciler that
# does not exist yet (gated on the nix-hapi core refactor).  Until then the
# manual procedures live in docs/nix-cache.org.
################################################################################
{
  config,
  facts,
  lib,
  pkgs,
  ...
}:
let
  inherit (facts.network) binaryCache domain;
  cacheName = binaryCache.atticCache;
  fqdn = "${binaryCache.atticAlias}.${domain}";
  port = 8095;
  localEndpoint = "http://127.0.0.1:${toString port}";
  dataDir = "/tank/data/attic/data";
  # The nixpkgs module keeps its checked config file private; this renders the
  # same settings for atticadm.
  serverToml =
    (pkgs.formats.toml { }).generate "attic-server.toml"
      config.services.atticd.settings;
  pubFile = ../secrets/generated/attic-signing-key.pub;
  signingPublicKey =
    assert lib.assertMsg (builtins.pathExists pubFile) ''
      ${toString pubFile} is missing or not tracked by git.  Run
      `agenix rekey generate --rekey --add-to-git` and commit the .pub sidecar
      first.
    '';
    lib.trim (builtins.readFile pubFile);
  jwtSecret = config.age.secrets.attic-server-jwt-environment-file;
  signingKeySecret = config.age.secrets.attic-signing-key;
  attic-cache-ensure =
    pkgs.callPackage ../derivations/attic-cache-ensure/default.nix
      {
        attic-server = config.services.atticd.package;
      };
  attic-watch-store =
    pkgs.callPackage ../derivations/attic-watch-store/default.nix
      {
        attic-server = config.services.atticd.package;
      };
  # TODO:  Let's make a helper or DI injected object out of this so it's easy to
  # perform service hardening in the future for any service.
  hardening = {
    CapabilityBoundingSet = "";
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [ "@system-service" ];
    UMask = "0077";
  };
in
{
  age.secrets.attic-server-jwt-environment-file = {
    generator.script = "attic-server-jwt-environment-file";
  };
  age.secrets.attic-signing-key = {
    generator.script = "nix-cache-signing-key";
    settings.keyName = "${cacheName}-1";
  };

  services.atticd = {
    enable = true;
    environmentFile = jwtSecret.path;
    settings = {
      listen = "127.0.0.1:${toString port}";
      # Advertised to clients in cache-config responses, so even the local
      # pusher goes through nginx.
      api-endpoint = "https://${fqdn}/";
      # Exact Host-header matches, port included.
      allowed-hosts = [
        fqdn
        "127.0.0.1:${toString port}"
      ];
      database.url = "postgresql://atticd@localhost/atticd?host=/run/postgresql";
      storage = {
        type = "local";
        path = "${dataDir}/storage";
      };
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "3 months";
      };
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "atticd" ];
    ensureUsers = [
      {
        name = "atticd";
        ensureDBOwnership = true;
      }
    ];
  };

  # atticd runs with DynamicUser.  The static atticd user declared here is what
  # systemd then uses, which keeps /tank ownership stable across reboots and
  # lets PostgreSQL peer authentication map the uid to the atticd role.
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };
  users.groups.atticd = { };

  # Derived data: everything here can be rebuilt or re-pushed, so neither the
  # chunks nor a database dump are worth backing up.
  tankVolumes.volumes.attic = {
    group = "atticd";
    backupData = false;
  };
  # The module grants ReadWritePaths on the storage path, and namespace setup
  # fails if that path does not exist yet.
  systemd.tmpfiles.rules = [ "d ${dataDir}/storage 0700 atticd atticd -" ];

  systemd.services.atticd = {
    after = [ "run-agenix.d.mount" ];
    requires = [ "run-agenix.d.mount" ];
    unitConfig.RequiresMountsFor = [ dataDir ];
    restartTriggers = [ jwtSecret.file ];
  };

  networking.dnsAliases = [ binaryCache.atticAlias ];
  services.https.fqdns.${fqdn}.internalPort = port;
  # NAR uploads run to gigabytes; stream them straight through rather than
  # spooling to the root disk, and give the server time to chunk them.
  services.nginx.virtualHosts.${fqdn} = {
    extraConfig = "client_max_body_size 0;";
    locations."/".extraConfig = ''
      proxy_request_buffering off;
      proxy_buffering off;
      proxy_read_timeout 1h;
      proxy_send_timeout 1h;
    '';
  };

  systemd.services.attic-cache-ensure = {
    description = "Ensure Attic cache '${cacheName}' exists with the pinned signing key";
    after = [
      "atticd.service"
      "run-agenix.d.mount"
    ];
    wants = [ "atticd.service" ];
    requires = [ "run-agenix.d.mount" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [
      jwtSecret.file
      signingKeySecret.file
      serverToml
    ];
    environment = {
      ATTIC_CACHE_NAME = cacheName;
      ATTIC_LOCAL_ENDPOINT = localEndpoint;
      ATTIC_EXPECTED_PUBLIC_KEY = signingPublicKey;
      ATTIC_SERVER_CONFIG = "${serverToml}";
      ATTIC_CACHE_PRIORITY = toString binaryCache.atticPriority;
      ATTIC_UPSTREAM_CACHE_KEY_NAMES = "cache.nixos.org-1";
    };
    serviceConfig = hardening // {
      Type = "oneshot";
      RemainAfterExit = true;
      DynamicUser = true;
      EnvironmentFile = jwtSecret.path;
      LoadCredential = [ "signing-key:${signingKeySecret.path}" ];
      ExecStart = lib.getExe attic-cache-ensure;
      TimeoutStartSec = 180;
      PrivateUsers = true;
      ProtectProc = "invisible";
    };
  };

  systemd.services.attic-watch-store = {
    description = "Push new /nix/store paths to Attic cache '${cacheName}'";
    after = [
      "atticd.service"
      "attic-cache-ensure.service"
      "nginx.service"
      "nss-lookup.target"
      "nix-daemon.socket"
      "run-agenix.d.mount"
    ];
    # Pushes go to the public endpoint, so nginx and DNS must be up, but an
    # nginx reload must not take the watcher down with it.
    wants = [
      "atticd.service"
      "attic-cache-ensure.service"
      "nginx.service"
    ];
    requires = [ "run-agenix.d.mount" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [
      jwtSecret.file
      serverToml
    ];
    environment = {
      ATTIC_CACHE_NAME = cacheName;
      ATTIC_ENDPOINT = "https://${fqdn}/";
      ATTIC_SERVER_CONFIG = "${serverToml}";
      ATTIC_TOKEN_VALIDITY = "30d";
      ATTIC_PUSH_JOBS = "4";
      # Never let the client's bundled Nix library open the store directly.
      NIX_REMOTE = "daemon";
      HOME = "/run/attic-watch-store";
    };
    unitConfig = {
      StartLimitIntervalSec = 600;
      StartLimitBurst = 20;
    };
    serviceConfig = hardening // {
      Type = "simple";
      DynamicUser = true;
      RuntimeDirectory = "attic-watch-store";
      RuntimeDirectoryMode = "0700";
      EnvironmentFile = jwtSecret.path;
      ExecStart = lib.getExe attic-watch-store;
      Restart = "always";
      RestartSec = 15;
      # A periodic restart re-mints the token well inside its validity.
      RuntimeMaxSec = "7d";
    };
  };

  services.goss.checks = {
    http."https://${fqdn}/${cacheName}/nix-cache-info" = {
      status = 200;
      timeout = 3000;
    };
    port."tcp:${toString port}" = {
      listening = true;
      ip = [ "127.0.0.1" ];
    };
    service.atticd = {
      enabled = true;
      running = true;
    };
    service.attic-watch-store = {
      enabled = true;
      running = true;
    };
    service.attic-cache-ensure = {
      enabled = true;
      # Oneshot: running is false once it has exited cleanly.
    };
  };
}
