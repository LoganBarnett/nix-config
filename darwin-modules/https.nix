################################################################################
# Provides HTTPS reverse proxying via nginx on macOS, implementing the
# services.https options from agnostic-modules/https.nix with a launchd
# daemon.  Only loopback TCP upstreams with internal-CA certificates are
# supported: launchd user agents offer no systemd-style group/umask plumbing
# that would let nginx's unprivileged workers open a service's unix socket,
# and nothing on darwin needs ACME or per-address binding yet.  Unsupported
# declarations fail eval via assertions rather than being silently ignored.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.https;
  fqdns = lib.filter (fqdn-cfg: fqdn-cfg.enable) (
    lib.attrsets.attrValues cfg.fqdns
  );
  active = cfg.enable && fqdns != [ ];
  externalPorts = lib.unique (map (fqdn-cfg: fqdn-cfg.externalPort) fqdns);
  # The NixOS module's recommendedProxySettings are not available here, so the
  # standard proxy and websocket-upgrade headers are spelled out per server
  # block.
  serverBlock = fqdn-cfg: ''
    server {
      listen ${toString fqdn-cfg.externalPort} ssl;
      server_name ${fqdn-cfg.fqdn};
      ssl_certificate ${../secrets/tls-${fqdn-cfg.fqdn}.crt};
      ssl_certificate_key ${config.age.secrets."tls-${fqdn-cfg.fqdn}.key".path};
      location / {
        proxy_pass http://127.0.0.1:${toString fqdn-cfg.internalPort};
        proxy_http_version 1.1;
        proxy_pass_header Authorization;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
      }
    }
  '';
  nginxConf = pkgs.writeText "https-nginx.conf" ''
    pid /tmp/https-nginx.pid;
    error_log /var/log/https-nginx.log warn;

    events {
      worker_connections 64;
    }

    http {
      access_log off;
      client_body_temp_path /tmp;
      proxy_temp_path /tmp;
      ssl_protocols TLSv1.2 TLSv1.3;
      ssl_prefer_server_ciphers off;

      map $http_upgrade $connection_upgrade {
        default upgrade;
        "" close;
      }

      # One default-deny block per listen port so that unmatched SNI gets a
      # hard TLS rejection rather than serving a stale or mismatched
      # certificate.
      ${lib.concatMapStrings (port: ''
        server {
          listen ${toString port} ssl default_server;
          ssl_reject_handshake on;
        }
      '') externalPorts}
      ${lib.concatMapStrings serverBlock fqdns}
    }
  '';
in
{
  imports = [
    ../agnostic-modules/https.nix
    ../agnostic-modules/tls-leaf.nix
    ./log-rotation.nix
  ];

  config = lib.mkIf active {
    assertions = [
      {
        assertion = cfg.domains == { };
        message = "https (darwin): domains policies (per-address binding, ACME) are unsupported; only the fallback behaviour (all interfaces, internal CA) is implemented.";
      }
    ]
    ++ map (fqdn-cfg: {
      assertion =
        fqdn-cfg.proxy
        && fqdn-cfg.internalPort != null
        && fqdn-cfg.socket == null
        && fqdn-cfg.serviceNameForSocket == null;
      message = "https (darwin): ${fqdn-cfg.fqdn} must use internalPort; socket upstreams and proxy = false are unsupported on darwin.";
    }) fqdns;

    tls.tls-leafs = lib.mkMerge (
      map (fqdn-cfg: {
        "${fqdn-cfg.fqdn}" = {
          inherit (fqdn-cfg) fqdn;
          ca = config.age.secrets.proton-ca;
        };
      }) fqdns
    );

    services.log-rotation.files.https-nginx.path = "/var/log/https-nginx.log";

    # Dial-based reachability stands in for the Linux implementation's
    # ss(8)-based port-bound check; iproute2 has no darwin build.
    services.goss.checks.addr = lib.listToAttrs (
      map (port: {
        name = "tcp://127.0.0.1:${toString port}";
        value = {
          reachable = true;
          timeout = 1000;
        };
      }) externalPorts
    );

    # The binary path is re-registered on every activation because it changes
    # when the nginx derivation is updated.
    system.activationScripts.postActivation.text = ''
      /usr/libexec/ApplicationFirewall/socketfilterfw \
        --add ${pkgs.nginx}/bin/nginx >/dev/null 2>&1 || true
      /usr/libexec/ApplicationFirewall/socketfilterfw \
        --unblockapp ${pkgs.nginx}/bin/nginx >/dev/null 2>&1 || true
    '';

    launchd.daemons.https-nginx = {
      serviceConfig = {
        Label = "org.https.nginx";
        # nginx has no long-form flags: -c names the configuration file and -g
        # sets a global directive.
        ProgramArguments = [
          "${pkgs.nginx}/bin/nginx"
          "-c"
          "${nginxConf}"
          "-g"
          "daemon off;"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardErrorPath = "/var/log/https-nginx.log";
      };
    };
  };
}
