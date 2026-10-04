################################################################################
# Register SSH public keys on gitea accounts from Nix.
#
# gitea keeps account SSH keys in its database and offers no CLI for them, so a
# provisioning unit registers each declared key through the REST API, using a
# token the gitea CLI mints for the owning account.  Keys already present are
# left untouched; removal is not handled.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.services.gitea-ssh-keys;
  gitea-ssh-keys = pkgs.callPackage ../derivations/gitea-ssh-keys/default.nix { };
  specJson = pkgs.writeText "gitea-ssh-keys.json" (
    builtins.toJSON (
      lib.mapAttrsToList (name: key: {
        inherit (key)
          title
          user
          publicKeyFile
          readOnly
          ;
      }) cfg.keys
    )
  );
in
{
  options.services.gitea-ssh-keys = {
    apiUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:${toString config.services.gitea.settings.server.HTTP_PORT}/api/v1";
      description = "gitea API base, reached over loopback.";
    };

    keys = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              title = mkOption {
                type = types.str;
                default = name;
                description = "Key title as shown in gitea.";
              };
              user = mkOption {
                type = types.str;
                description = "gitea account that receives the key.";
              };
              publicKeyFile = mkOption {
                type = types.path;
                description = "OpenSSH public key file.";
              };
              readOnly = mkOption {
                type = types.bool;
                default = false;
                description = "Whether the key may only pull.";
              };
            };
          }
        )
      );
      default = { };
      description = "SSH public keys to register, keyed by title.";
    };
  };

  config = mkIf (cfg.keys != { }) {
    systemd.services.gitea-ssh-keys = {
      description = "Register declared SSH keys on gitea accounts";
      after = [ "gitea.service" ];
      wants = [ "gitea.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ specJson ];
      environment = {
        GITEA_SSH_KEYS_SPEC = "${specJson}";
        GITEA_BIN = lib.getExe config.services.gitea.package;
        GITEA_APP_INI = "${config.services.gitea.customDir}/conf/app.ini";
        GITEA_API = cfg.apiUrl;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # The gitea CLI needs the same database access as the server.
        User = config.services.gitea.user;
        Group = config.services.gitea.group;
        StateDirectory = "gitea-ssh-keys";
        StateDirectoryMode = "0700";
        ExecStart = lib.getExe gitea-ssh-keys;
      };
    };
  };
}
