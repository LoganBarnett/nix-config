################################################################################
# Registers one read-only mcp-grafana MCP server per Grafana instance for the
# primary user, each backed by its own issued service-account token.
#
# mcp-grafana in stdio mode serves a single Grafana per process and takes its
# URL only from the GRAFANA_URL environment variable, so every instance gets its
# own wrapper script and its own `programs.mcp.servers` entry, named
# `grafana-<instance>`.  The token is read at run time from the agenix secret
# `grafana-<instance>-mcp-token`, which this module declares; nothing secret
# lands in the Nix store.
#
# `rekeyFile` has no default on purpose.  A default resolving inside this flake
# would make a private wrapper flake's secret "owned" by nix-config as far as
# agenix-rekey is concerned, which is exactly what a wrapper must avoid.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    literalExpression
    mapAttrs'
    mkIf
    mkOption
    nameValuePair
    types
    ;
  inherit (pkgs.callPackage ../lib/credential-preamble.nix { }) fileToken;

  cfg = config.services.mcp.grafana;
  enabled = lib.filterAttrs (_: instance: instance.enable) cfg.instances;
  secretName = instance: "grafana-${instance}-mcp-token";

  # `--disable-write` and `--disable-admin` keep the tool surface read-only.
  # `--enabled-tools` narrows it further if that is still too broad.  The token
  # should belong to a Viewer-role service account so the credential itself is
  # read-only, not just the tool flags.  It is exported under both environment
  # variable names mcp-grafana has accepted across versions.
  wrapper =
    instance: url:
    pkgs.writeShellScript "grafana-${instance}-mcp-wrapped" ''
      set -euo pipefail
      ${fileToken config.age.secrets.${secretName instance}.path}
      export GRAFANA_URL=${lib.escapeShellArg url}
      export GRAFANA_API_KEY="$token"
      export GRAFANA_SERVICE_ACCOUNT_TOKEN="$token"
      exec ${pkgs.mcp-grafana}/bin/mcp-grafana \
        --transport stdio \
        --disable-write \
        --disable-admin
    '';
in
{
  options.services.mcp.grafana = {
    user = mkOption {
      type = types.str;
      default = config.system.primaryUser;
      defaultText = literalExpression "config.system.primaryUser";
      description = ''
        Login user whose MCP registry receives the servers and who owns the
        token secrets.  NixOS has no `system.primaryUser`, so NixOS hosts must
        set this explicitly.
      '';
    };
    instances = mkOption {
      default = { };
      description = ''
        Grafana instances to expose, keyed by instance name.  Each enabled
        instance yields the MCP server `grafana-<name>` and the agenix secret
        `grafana-<name>-mcp-token`.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Whether to register this instance.  Disable an instance whose
                token has not been issued yet.  Its `rekeyFile` is then never
                read.
              '';
            };
            url = mkOption {
              type = types.str;
              description = "Base URL of the Grafana instance.";
            };
            rekeyFile = mkOption {
              type = types.path;
              description = ''
                The issued service-account token, encrypted for agenix-rekey.
                By convention
                `secrets/issued/grafana-<instance>-<host-id>-mcp-token.age` in
                the flake that owns the instance.
              '';
            };
          };
        }
      );
    };
  };

  config = mkIf (enabled != { }) {
    age.secrets = mapAttrs' (
      instance: inst:
      nameValuePair (secretName instance) {
        inherit (inst) rekeyFile;
        # The wrapper runs as the login user, not as root.
        mode = "0400";
        owner = cfg.user;
      }
    ) enabled;

    home-manager.users.${cfg.user}.programs.mcp = {
      enable = true;
      servers = mapAttrs' (
        instance: inst:
        nameValuePair "grafana-${instance}" {
          type = "stdio";
          command = "${wrapper instance inst.url}";
        }
      ) enabled;
    };
  };
}
