################################################################################
# Option declarations for HTTPS reverse proxying via nginx.  Per-platform
# modules provide the implementation.
################################################################################
{
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    ;
in
{
  options = {
    services.https = {
      enable = mkEnableOption "Short-hand nginx settings." // {
        default = true;
      };
      fqdns = mkOption (
        let
          # Note: The destructuring form in Nix is not just syntax sugar.  If I
          # treated this as a single variable (e.g. `submodule`) and referenced
          # the name field (`submodule.name`), this would create infinite
          # recursion.
          fqdn-type = types.submodule (
            { name, ... }:
            {
              options = {
                enable = mkEnableOption "Reverse proxies for FQDNs." // {
                  default = true;
                };
                fqdn = mkOption {
                  type = types.str;
                  readOnly = true;
                  internal = true;
                  default = name;
                };
                proxy = mkOption {
                  type = types.bool;
                  default = true;
                  description = ''
                    Setup a reverse proxy for TLS.  Typically we want this on, but PHP
                    generally want this off since they are running nginx already.
                  '';
                };
                internalPort = mkOption {
                  type = types.nullOr types.port;
                  default = null;
                  description = "Internal TCP port for the upstream service.";
                };
                socket = mkOption {
                  type = types.nullOr types.path;
                  default = null;
                  description = ''
                    Unix domain socket path for the upstream service.  The service is
                    responsible for creating the socket with permissions that allow
                    the nginx-upstream group to connect.
                  '';
                };
                serviceNameForSocket = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    Name of the upstream service that creates its own socket at
                    /run/<name>/<name>.sock.  https sets UMask = 0007 and
                    RuntimeDirectoryMode = 0750 on the service so the socket is
                    group-writable and the directory is traversable.  nginx is
                    added to the socket's owning group (socketGroup if set,
                    otherwise the service name).
                  '';
                };
                socketGroup = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    Override the group that owns the socket created by
                    serviceNameForSocket.  Defaults to serviceNameForSocket when
                    null.  Set this when the socket unit sets SocketGroup to a
                    name that differs from the service name, such as when systemd
                    socket activation manages the socket rather than the service
                    process itself.
                  '';
                };
                externalPort = mkOption {
                  type = types.port;
                  default = 443;
                };
              };
            }
          );
        in
        {
          type = types.attrsOf fqdn-type;
          default = { };
        }
      );
      domains = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              addr = mkOption {
                type = types.str;
                description = "IP address nginx should listen on for this domain suffix.";
              };
              certSource = mkOption {
                type = types.enum [
                  "internal-ca"
                  "acme"
                ];
                description = "Certificate source: internal CA or ACME DNS-01.";
              };
            };
          }
        );
        default = { };
        description = ''
          Domain-suffix policies mapping a suffix (e.g. "proton", "example.com")
          to a listen address and certificate source.  Every FQDN in fqdns
          inherits its policy via longest-suffix match.  When empty the module
          falls back to the pre-domains behaviour: listen on all interfaces,
          internal-CA cert for every FQDN.
        '';
      };
    };
  };
}
