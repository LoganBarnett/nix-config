################################################################################
# Work around c-ares's inability to use scoped (zone-qualified) nameservers.
#
# Cellular tethers on IPv6-only carriers hand out their sole nameserver via
# DHCPv6 as a link-local address, which macOS records as e.g.
# "nameserver fe80::1%en0".  Apple's resolver handles the zone, but c-ares
# does not, so every Nix-built libcurl consumer (curl, git, nix-daemon) dies
# with "Could not contact DNS servers".  The fix is a local dnsmasq forwarder
# on 127.0.0.1 — an address c-ares can always reach — whose upstreams are
# kept current by dnsmasq-upstream-sync, which harvests DHCPv4 and DHCPv6
# nameservers and writes scoped literals that dnsmasq accepts.  See
# docs/tether-dns.org for the full design; this module is its M1a, lifted
# from the dormant GlobalProtect module which becomes a consumer in M2.
#
# The forwarder also reads drop-in fragments from a conf-dir so reconcilers
# (e.g. the deferred filter-AAAA tether knob, M1b) can adjust behavior
# without touching this module.
#
# Disabling this module does not revert the DNS takeover: every network
# service keeps pointing at 127.0.0.1 with no dnsmasq behind it.  Restore
# per-service DHCP DNS with `networksetup -setdnsservers <service> Empty`.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dns-c-ares-scopeless-fix;

  dnsmasqUpstreamSync =
    pkgs.callPackage ../derivations/dnsmasq-upstream-sync/default.nix
      { };

  dnsmasqConf = pkgs.writeText "dns-c-ares-scopeless-fix-dnsmasq.conf" ''
    # Listen only on localhost so dnsmasq does not conflict with
    # mDNSResponder on the wildcard address.
    listen-address=127.0.0.1
    bind-interfaces

    # Upstream DNS discovered by dnsmasq-upstream-sync via DHCPv4/DHCPv6.
    # dnsmasq polls this file for changes automatically and tolerates its
    # absence, so nothing needs to pre-create it.
    resolv-file=${cfg.upstreamResolvFile}

    # Static domain forwarding (e.g. proton -> home DNS).
    ${lib.concatMapStringsSep "\n" (
      e: "server=/${e.domain}/${e.server}"
    ) cfg.domainForwarding}

    # Drop-in fragments from reconcilers.  Options placed here are
    # main-config options: they need a dnsmasq restart (launchctl
    # kickstart), not SIGHUP.
    conf-dir=${cfg.confDir},*.conf

    # Sane defaults for a local forwarder.
    cache-size=${toString cfg.cacheSize}
    domain-needed
    bogus-priv
  '';

  # /var/run is cleared at every boot and dnsmasq exits fatally ("cannot
  # access directory") when its conf-dir is missing, so the directory must
  # be recreated before every start.  This cannot be inlined into the
  # launchd `command` below because nix-darwin wraps that value in
  # `/bin/sh -c "/bin/wait4path /nix/store && exec …"`, whose `exec` would
  # swallow a compound command.
  dnsmasqStart = pkgs.writeShellScript "dns-c-ares-scopeless-fix-dnsmasq-start" ''
    /bin/mkdir -p ${cfg.confDir}
    exec ${pkgs.dnsmasq}/bin/dnsmasq \
      --keep-in-foreground \
      --conf-file=${dnsmasqConf}
  '';
in
{
  options.services.dns-c-ares-scopeless-fix = {
    enable = lib.mkEnableOption "the c-ares scopeless-nameserver DNS fix";

    confDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/run/dnsmasq.d";
      description = ''
        Directory of dnsmasq drop-in fragments (*.conf) read in addition
        to the main configuration.  Reconcilers write here.
      '';
    };

    domainForwarding = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            domain = lib.mkOption {
              type = lib.types.str;
              description = "Domain to forward (e.g. proton).";
            };
            server = lib.mkOption {
              type = lib.types.str;
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

    upstreamResolvFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/run/dnsmasq-upstream-resolv.conf";
      description = ''
        Path for the upstream resolv.conf written by dnsmasq-upstream-sync
        from DHCP-provided DNS.
      '';
    };

    cacheSize = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Number of DNS cache entries for dnsmasq.";
    };

    syncInterval = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = ''
        Seconds between upstream DNS discovery checks by
        dnsmasq-upstream-sync.
      '';
    };
  };

  imports = [ ./log-rotation.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # Both modules declare launchd.daemons.dnsmasq.  The GlobalProtect
        # module keeps its own copy until M2 makes it a consumer of this
        # one; attrByPath keeps evaluation working on hosts that do not
        # import the GlobalProtect module at all.
        assertion =
          !(lib.attrByPath [
            "services"
            "globalprotect-monitor"
            "enable"
          ] false config);
        message = ''
          services.dns-c-ares-scopeless-fix and
          services.globalprotect-monitor both stand up the dnsmasq daemon;
          keep GlobalProtect dormant until it becomes a consumer
          (docs/tether-dns.org, M2).
        '';
      }
      {
        assertion = !config.services.dnsmasq.enable;
        message = ''
          services.dns-c-ares-scopeless-fix conflicts with nix-darwin's
          built-in services.dnsmasq; enable only one.
        '';
      }
    ];

    environment.systemPackages = [
      pkgs.dnsmasq
      dnsmasqUpstreamSync
    ];

    # Point every network service's DNS at the local forwarder.  macOS then
    # writes 127.0.0.1 into /var/run/resolv.conf itself, which is what
    # c-ares clients read via the /etc/resolv.conf symlink.  The conf-dir
    # mkdir covers enabling without a reboot; the daemon start wrapper owns
    # the every-boot case.
    system.activationScripts.postActivation.text = ''
      /bin/mkdir -p ${cfg.confDir}
      /usr/sbin/networksetup -listallnetworkservices | tail -n +2 | while IFS= read -r svc; do
        case "$svc" in
          # A leading asterisk marks a disabled service; networksetup
          # rejects the starred name outright, so skip it explicitly
          # rather than suppressing the error.
          '*'*) continue ;;
        esac
        /usr/sbin/networksetup -setdnsservers "$svc" 127.0.0.1 \
          || echo "warning: could not point DNS at 127.0.0.1 for service: $svc" >&2
      done
    '';

    # These daemons use `command` rather than raw ProgramArguments so
    # nix-darwin wraps them in `/bin/wait4path /nix/store && exec …`.
    # Without the guard, launchd can attempt the first spawn before the
    # Nix store volume mounts at boot, fail with EX_CONFIG, and wedge on
    # an executable-appeared watch that never fires for the synthetic
    # /nix mount.
    launchd.daemons.dnsmasq = {
      command = "${dnsmasqStart}";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/var/log/dnsmasq.log";
        StandardErrorPath = "/var/log/dnsmasq.log";
      };
    };

    # Companion daemon that discovers DHCP-provided DNS from the active
    # interface and writes it to the upstream resolv file for dnsmasq.
    launchd.daemons.dnsmasq-upstream-sync = {
      command = "${dnsmasqUpstreamSync}/bin/dnsmasq-upstream-sync";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        EnvironmentVariables = {
          DNSMASQ_UPSTREAM_RESOLV_FILE = cfg.upstreamResolvFile;
          DNSMASQ_SYNC_INTERVAL = toString cfg.syncInterval;
        };
        StandardOutPath = "/var/log/dnsmasq-upstream-sync.log";
        StandardErrorPath = "/var/log/dnsmasq-upstream-sync.log";
      };
    };

    services.log-rotation.files = {
      dnsmasq.path = "/var/log/dnsmasq.log";
      dnsmasq-upstream-sync.path = "/var/log/dnsmasq-upstream-sync.log";
    };
  };
}
