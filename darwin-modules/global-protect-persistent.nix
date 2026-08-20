################################################################################
# GlobalProtect VPN persistent connection service for nix-darwin.
# Automatically connects and maintains VPN connection using gp-connect-auto.
# Runs as a system daemon (root) to allow VPN tunnel creation while accessing
# the primary user's gpg keys and pass password store for authentication.
#
# Also provides a local dnsmasq forwarder on 127.0.0.1:53 so that Nix-compiled
# tools (curl with c-ares, git, dig) can resolve VPN domains through
# /etc/resolv.conf instead of relying on macOS /etc/resolver/ split-DNS.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let

  cfg = config.services.globalprotect-monitor;
  dnsCfg = cfg.dnsmasq;

  monitorScript = pkgs.writeShellScript "gp-monitor-wrapper" ''
    set -e

    # Configuration from Nix options - these match what gp-connect-auto expects
    export GP_SERVER="${cfg.server}"
    ${optionalString (cfg.gateway != null) ''export GP_GATEWAY="${cfg.gateway}"''}
    export GP_USERNAME="${cfg.username}"
    export ORG_NAME="${cfg.orgName}"
    export GP_CHECK_INTERVAL="${toString cfg.checkInterval}"
    export GP_LOG_DIR="${cfg.logDir}"
    # Use ${"$"}{VAR:=default} so an externally-set GP_AUTO_CONFIG (e.g.
    # for ad-hoc testing) is honored, with cfg.configFile as the fallback.
    # launchd's env is empty by default, so the daemon path always lands
    # on the fallback unless someone explicitly sets it.
    : "''${GP_AUTO_CONFIG:=${cfg.configFile}}"
    export GP_AUTO_CONFIG

    # Create log directory (running as user, ownership is automatic)
    mkdir -p "$GP_LOG_DIR"

    # Run the monitor script
    exec ${cfg.package}/bin/gp-monitor
  '';

  dnsmasqConf = pkgs.writeText "dnsmasq.conf" ''
    # Listen only on localhost so dnsmasq does not conflict with
    # mDNSResponder on the wildcard address.
    listen-address=127.0.0.1
    bind-interfaces

    # Upstream DNS discovered by dnsmasq-upstream-sync via DHCP.
    # dnsmasq polls this file for changes automatically.
    resolv-file=${dnsCfg.upstreamResolvFile}

    # VPN domain-specific servers written by vpnc-script-macos on connect
    # and cleared on disconnect.  Reloaded on SIGHUP.
    servers-file=${dnsCfg.vpnServersFile}

    # Static domain forwarding (e.g. proton -> home DNS).
    ${concatMapStringsSep "\n" (
      e: "server=/${e.domain}/${e.server}"
    ) dnsCfg.domainForwarding}

    # Sane defaults for a local forwarder.
    cache-size=${toString dnsCfg.cacheSize}
    domain-needed
    bogus-priv
  '';

  dnsmasqUpstreamSync =
    pkgs.callPackage ../derivations/dnsmasq-upstream-sync/default.nix
      { };

in
{
  options = {
    services.globalprotect-monitor = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable the GlobalProtect VPN monitor service.";
      };

      server = mkOption {
        type = types.str;
        example = "vpn.company.com";
        description = "The GlobalProtect portal server URL.";
      };

      gateway = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "gateway.company.com";
        description = ''
          The GlobalProtect gateway to connect to.
          If not specified, the portal will prompt for gateway selection.
        '';
      };

      username = mkOption {
        type = types.str;
        example = "john.doe@company.com";
        description = "The VPN username/email to use for authentication.";
      };

      orgName = mkOption {
        type = types.str;
        example = "company";
        description = ''
          The organization name used for pass password store entries.
          This is used to retrieve credentials from pass (e.g., 'pass show <orgName>').
        '';
      };

      primaryUser = mkOption {
        type = types.str;
        default = "logan.barnett";
        example = "john.doe";
        description = ''
          The primary user whose gpg keys and pass store will be used.
          The service runs as root but accesses this user's credentials.
        '';
      };

      checkInterval = mkOption {
        type = types.int;
        default = 60;
        example = 120;
        description = ''
          Seconds between VPN connection checks.
          The service will check if the VPN is connected every N seconds.
        '';
      };

      reconnectTimeout = mkOption {
        type = types.int;
        default = 300;
        example = 600;
        description = ''
          Reconnection retry timeout in seconds.
          This is passed to gpclient's --reconnect-timeout option.
        '';
      };

      logDir = mkOption {
        type = types.str;
        default = "/Users/${cfg.primaryUser}/.local/share/gpclient/logs";
        example = "/Users/john.doe/.local/share/gpclient/logs";
        description = "Directory where VPN monitor logs will be stored.";
      };

      headlessBrowser = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to run the Chromium browser in headless mode during
          authentication.  Set to false to show the browser window for
          debugging SSO flows.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.callPackage ../derivations/gp-monitor.nix { };
        description = "The gp-monitor package to use.";
      };

      configFile = mkOption {
        type = types.str;
        default = "/etc/globalprotect-auto/config.json";
        description = ''
          Filesystem path of the JSON configuration file that this module
          writes and that all the GP/VPN scripts read at runtime via the
          `GP_AUTO_CONFIG` environment variable.  The value is exported
          three ways: `environment.variables.GP_AUTO_CONFIG` for
          interactive shells, the launchd-service wrapper for the
          gp-monitor daemon, and gp-connect-auto for the sudo path
          (sudo strips env by default, so the wrapper has to re-export
          it for gpclient and the vpnc-script-macos it spawns).  Each
          export uses `${"$"}{GP_AUTO_CONFIG:=...}` so an explicit
          override survives if one is present.  Must be under /etc/ —
          the file itself is written via `environment.etc`, which
          prefixes everything with /etc/.
        '';
      };

      fallbackSearchDomains = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "internal.example.com"
          "corp.example.com"
        ];
        description = ''
          DNS search domains used as a fallback when the VPN server does
          not push CISCO_SPLIT_DNS and macOS scutil has no domain hints.
          Written into the file at services.globalprotect-monitor.
          configFile; vpnc-script-macos and dns-vpn-scoping-fix read it
          via jq at runtime.  An empty list leaves the fallback path
          inert.
        '';
      };

      corpDomainSuffixes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "pvt"
          "example.com"
        ];
        description = ''
          Domain suffixes that identify corporate / VPN-routable DNS
          records.  Read at runtime from services.globalprotect-monitor.
          configFile; scripts build a grep regex from the list (each
          suffix `.`-escaped, joined by `|`) to filter scutil's search
          domains down to the corporate subset.
        '';
      };

      testHost = mkOption {
        type = types.str;
        default = "";
        example = "internal-service.corp.example.com";
        description = ''
          A hostname inside the corporate network that the VPN
          diagnostic scripts (gp-monitor, test-vpn-connectivity,
          vpn-test-harness) probe to decide whether DNS / connectivity
          is healthy.  Read at runtime from services.globalprotect-
          monitor.configFile.
        '';
      };

      localDnsServer = mkOption {
        type = types.str;
        default = "";
        example = "192.168.254.9";
        description = ''
          The host's authoritative local-network DNS server, used by
          dns-fix-complete to write the `proton` (or equivalent)
          resolver entry alongside the VPN-domain entries.  Typically
          derived per-host via `pkgs.lib.custom.networkDnsIp facts`.
          Read at runtime from services.globalprotect-monitor.
          configFile.
        '';
      };

      dnsmasq = {
        domainForwarding = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                domain = mkOption {
                  type = types.str;
                  description = "Domain to forward (e.g. proton).";
                };
                server = mkOption {
                  type = types.str;
                  description = "DNS server IP for this domain.";
                };
              };
            }
          );
          default = [ ];
          example = [
            {
              domain = "proton";
              server = "192.168.254.9";
            }
          ];
          description = "Static domain-specific DNS forwarding entries.";
        };

        vpnServersFile = mkOption {
          type = types.str;
          default = "/var/run/dnsmasq-vpn-servers.conf";
          description = ''
            Path for dynamic VPN domain servers written by vpnc-script-macos
            on connect and cleared on disconnect.
          '';
        };

        upstreamResolvFile = mkOption {
          type = types.str;
          default = "/var/run/dnsmasq-upstream-resolv.conf";
          description = ''
            Path for upstream resolv.conf written by dnsmasq-upstream-sync
            from DHCP-provided DNS.
          '';
        };

        cacheSize = mkOption {
          type = types.int;
          default = 1000;
          description = "Number of DNS cache entries for dnsmasq.";
        };

        syncInterval = mkOption {
          type = types.int;
          default = 30;
          description = ''
            Seconds between upstream DNS discovery checks by
            dnsmasq-upstream-sync.
          '';
        };
      };
    };
  };

  imports = [ ./log-rotation.nix ];

  config = mkIf cfg.enable {

    # configFile is written via environment.etc, which prepends /etc/, so the
    # option value has to start with /etc/ for the path to round-trip.
    assertions = [
      {
        assertion = lib.hasPrefix "/etc/" cfg.configFile;
        message = "services.globalprotect-monitor.configFile must start with /etc/ (got: ${cfg.configFile}).";
      }
    ];

    environment.systemPackages = [
      (pkgs.callPackage ../derivations/cleanup-vpn.nix { })
      (pkgs.callPackage ../derivations/dns-resolver-helper.nix { })
      (pkgs.callPackage ../derivations/dns-vpn-scoping-fix.nix { })
      (pkgs.callPackage ../derivations/dns-fix-complete.nix { })
      pkgs.dnsmasq
      dnsmasqUpstreamSync
      pkgs.gpclient
      # gp-connect-auto is the one wrapper that still needs configFile —
      # it inlines the default into its sudo-side `${"$"}{GP_AUTO_CONFIG:=
      # ...}` export so that gpclient and the vpnc-script-macos it
      # spawns see the path after sudo strips the inbound env.
      (pkgs.callPackage ../derivations/gp-connect-auto.nix {
        inherit (cfg) configFile;
      })
      pkgs.jq
      (pkgs.callPackage ../derivations/test-vpn-connectivity.nix { })
      (pkgs.callPackage ../derivations/vpn-test-harness-recover.nix { })
      (pkgs.callPackage ../derivations/vpn-test-harness.nix { })
    ];

    # Shared, world-readable configuration consumed by all the GP/VPN
    # scripts.  `/etc` rather than `~/.config` because vpnc-script-macos is
    # invoked by gpclient as root and would not have the primary user's
    # home in its environment; `/etc` lets root and user scripts read from
    # the same file without symlinks or env gymnastics.
    environment.etc.${lib.removePrefix "/etc/" cfg.configFile}.text =
      builtins.toJSON
        {
          inherit (cfg)
            fallbackSearchDomains
            corpDomainSuffixes
            testHost
            localDnsServer
            ;
        };

    # Expose the path as a system-wide environment variable so interactive
    # shells and ad-hoc invocations of the scripts read the same config the
    # daemon does.  The gp-monitor launchd wrapper (monitorScript) and
    # gp-connect-auto re-export this themselves to cover launchd's empty
    # env and sudo's env-stripping respectively.
    environment.variables.GP_AUTO_CONFIG = cfg.configFile;

    # Allow user to run specific commands without password for VPN automation.
    # 1. dns-resolver-helper: validates inputs and only operates on /etc/resolver
    # 2. gp-connect-auto: needs elevated privileges for tunnel creation
    # 3. cleanup-vpn: TEMPORARY for development - TODO: REMOVE BEFORE MERGE
    # 4. vpn-test-harness-recover: restores default gateway after VPN tunnel collapse
    security.sudo.extraConfig = ''
      ${cfg.primaryUser} ALL=(root) NOPASSWD: ${
        pkgs.callPackage ../derivations/dns-resolver-helper.nix { }
      }/bin/dns-resolver-helper *
      ${cfg.primaryUser} ALL=(root) NOPASSWD: SETENV: ${
        pkgs.callPackage ../derivations/gp-connect-auto.nix { }
      }/bin/gp-connect-auto
      ${cfg.primaryUser} ALL=(root) NOPASSWD: ${
        pkgs.callPackage ../derivations/cleanup-vpn.nix { }
      }/bin/cleanup-vpn
      ${cfg.primaryUser} ALL=(root) NOPASSWD: SETENV: ${
        pkgs.callPackage ../derivations/vpn-test-harness-recover.nix { }
      }/bin/vpn-test-harness-recover
      # Allow manual DHCP renewal and network reset for post-VPN-disconnect recovery.
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/ipconfig set * DHCP
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setdhcp *
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setdnsservers * Empty
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setdnsservers * 127.0.0.1
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setsearchdomains * Empty
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setwebproxystate * Off
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setsecurewebproxystate * Off
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setv6automatic *
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setproxybypassdomains * Empty
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setnetworkserviceenabled * Off
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/sbin/networksetup -setnetworkserviceenabled * On
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/bin/dscacheutil -flushcache
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/bin/killall -HUP mDNSResponder
      ${cfg.primaryUser} ALL=(root) NOPASSWD: /usr/bin/killall -HUP dnsmasq
      ${cfg.primaryUser} ALL=(root) NOPASSWD: SETENV: ${
        pkgs.callPackage ../derivations/vpn-test-harness.nix { }
      }/bin/vpn-test-harness *
    '';

    # Ensure dnsmasq data files exist before dnsmasq starts, and point
    # all network services' DNS to 127.0.0.1 so every tool (Nix and
    # native) resolves through dnsmasq.
    system.activationScripts.postActivation.text =
      let
        vpnServersFile = dnsCfg.vpnServersFile;
        upstreamResolvFile = dnsCfg.upstreamResolvFile;
      in
      ''
        # dnsmasq data files: touch so dnsmasq does not fail on first boot.
        if [ ! -f "${vpnServersFile}" ]; then
          touch "${vpnServersFile}"
        fi
        if [ ! -f "${upstreamResolvFile}" ]; then
          # Seed with a sane default so DNS works before the first sync.
          echo "nameserver 192.168.254.9" > "${upstreamResolvFile}"
        fi

        # Point all network services' DNS to 127.0.0.1 (dnsmasq).
        /usr/sbin/networksetup -listallnetworkservices | tail -n +2 | while IFS= read -r svc; do
          /usr/sbin/networksetup -setdnsservers "$svc" 127.0.0.1 2>/dev/null || true
        done
      '';

    # dnsmasq local DNS forwarder — always active when the module is
    # imported.  VPN DNS resolution is inseparable from the VPN service.
    #
    # These daemons use `command` rather than raw ProgramArguments so
    # nix-darwin wraps them in `/bin/wait4path /nix/store && exec …`.
    # Without the guard, launchd can attempt the first spawn before the
    # Nix store volume mounts at boot, fail with EX_CONFIG, and wedge on
    # an executable-appeared watch that never fires for the synthetic
    # /nix mount.
    launchd.daemons.dnsmasq = {
      command = "${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --conf-file=${dnsmasqConf}";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/var/log/dnsmasq.log";
        StandardErrorPath = "/var/log/dnsmasq.log";
      };
    };

    # Companion daemon that discovers DHCP DNS from the active interface
    # and writes it to the upstream resolv file for dnsmasq.
    launchd.daemons.dnsmasq-upstream-sync = {
      command = "${dnsmasqUpstreamSync}/bin/dnsmasq-upstream-sync";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        EnvironmentVariables = {
          DNSMASQ_UPSTREAM_RESOLV_FILE = dnsCfg.upstreamResolvFile;
          DNSMASQ_SYNC_INTERVAL = toString dnsCfg.syncInterval;
        };
        StandardOutPath = "/var/log/dnsmasq-upstream-sync.log";
        StandardErrorPath = "/var/log/dnsmasq-upstream-sync.log";
      };
    };

    launchd.daemons.globalprotect-monitor = {
      path = [ config.environment.systemPath ];
      command = "${pkgs.bash}/bin/bash ${monitorScript}";

      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;

        # Run as primary user
        UserName = cfg.primaryUser;
        GroupName = "staff";

        # Environment variables - these match what gp-connect-auto expects
        EnvironmentVariables = {
          GP_SERVER = cfg.server;
          GP_USERNAME = cfg.username;
          ORG_NAME = cfg.orgName;
          GP_CHECK_INTERVAL = toString cfg.checkInterval;
          GP_LOG_DIR = cfg.logDir;
          GP_BROWSER_HEADLESS = if cfg.headlessBrowser then "true" else "false";
        }
        // (optionalAttrs (cfg.gateway != null) {
          GP_GATEWAY = cfg.gateway;
        });

        # Logging
        StandardOutPath = "${cfg.logDir}/launchd-stdout.log";
        StandardErrorPath = "${cfg.logDir}/launchd-stderr.log";
      };
    };

    # Every log this module emits, registered for rotation.  monitor.log is
    # written both by gp-monitor's log() and by gpclient through an inherited
    # descriptor; the launchd pair is the daemon's raw stdout/stderr.  Those
    # three live in the primary user's home, so logrotate needs the `su`
    # identity.  The dnsmasq pair is root-owned under /var/log and needs
    # nothing extra.
    services.log-rotation.files = {
      gp-monitor = {
        path = "${cfg.logDir}/monitor.log";
        user = cfg.primaryUser;
      };
      gp-monitor-launchd-stdout = {
        path = "${cfg.logDir}/launchd-stdout.log";
        user = cfg.primaryUser;
      };
      gp-monitor-launchd-stderr = {
        path = "${cfg.logDir}/launchd-stderr.log";
        user = cfg.primaryUser;
      };
      dnsmasq.path = "/var/log/dnsmasq.log";
      dnsmasq-upstream-sync.path = "/var/log/dnsmasq-upstream-sync.log";
    };
  };
}
