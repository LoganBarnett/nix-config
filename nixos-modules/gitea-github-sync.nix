################################################################################
# Periodically pull GitHub into the gitea copies of the same repositories.
#
# gitea.proton is where unpublished work lands first, so it is allowed to run
# ahead of GitHub.  This job only ever moves gitea forward: fast-forwards when
# gitea is behind, rebases gitea-only commits onto GitHub when both sides moved,
# and fails loudly when that rebase conflicts.  The existing systemd_unit_down
# alert pages on the failed unit; nothing else is needed for notification.
#
# A rebase rewrites the gitea-only commits, so a clone tracking gitea needs a
# `git pull --rebase` afterwards and the private flake lock needs its usual
# bump.  That is the price of letting GitHub move independently.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.services.gitea-github-sync;
  gitea-github-sync =
    pkgs.callPackage ../derivations/gitea-github-sync/default.nix
      { };
  reposJson = pkgs.writeText "gitea-github-sync-repos.json" (
    builtins.toJSON (
      lib.mapAttrsToList (name: repo: {
        inherit name;
        inherit (repo) github gitea branches;
      }) cfg.repos
    )
  );
  credentialsDirectory = "/run/credentials/gitea-github-sync.service";
in
{
  options.services.gitea-github-sync = {
    enable = mkEnableOption "pulling GitHub into the gitea mirrors on a timer";

    githubOwner = mkOption {
      type = types.str;
      default = "LoganBarnett";
      description = "GitHub owner that repositories default to.";
    };

    giteaUrlBase = mkOption {
      type = types.str;
      default = "ssh://git@gitea.proton:2222/logan";
      description = ''
        Prefix for gitea repository URLs, including the owner.  SSH is the only
        transport whose identity can be scoped to this unit.
      '';
    };

    sshKeyFile = mkOption {
      type = types.path;
      description = ''
        Private key whose public half is registered with gitea for an account
        allowed to push to every configured repository.  Loaded as a systemd
        credential; the file itself may be root-only.
      '';
    };

    interval = mkOption {
      type = types.str;
      default = "30min";
      description = "Time between runs, as a systemd time span.";
    };

    committer = {
      name = mkOption {
        type = types.str;
        default = "gitea-github-sync";
        description = "Committer name stamped on rebased commits.";
      };
      email = mkOption {
        type = types.str;
        default = "gitea-github-sync@${config.networking.hostName}";
        description = "Committer email stamped on rebased commits.";
      };
    };

    repos = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              github = mkOption {
                type = types.str;
                default = "https://github.com/${cfg.githubOwner}/${name}.git";
                description = ''
                  GitHub clone URL.  HTTPS needs no credential for a public
                  repository.
                '';
              };
              gitea = mkOption {
                type = types.str;
                default = "${cfg.giteaUrlBase}/${name}.git";
                description = "gitea push URL.";
              };
              branches = mkOption {
                type = types.listOf types.str;
                default = [ "main" ];
                description = ''
                  Branches to reconcile.  Each must exist on GitHub.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = "Repositories to reconcile, keyed by their shared name.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.gitea-github-sync = {
      description = "Pull GitHub into the gitea mirrors";
      # Resolves and reaches gitea.proton and github.com at runtime, so gate on
      # DNS and the network rather than racing a resolver restart.
      after = [
        "gitea.service"
        "network-online.target"
        "nss-lookup.target"
        "run-agenix.d.mount"
      ];
      wants = [
        "gitea.service"
        "network-online.target"
        "nss-lookup.target"
      ];
      requires = [ "run-agenix.d.mount" ];
      # No wantedBy: the timer is the sole activator, so a GitHub outage at boot
      # or deploy time cannot leave the host degraded.
      environment = {
        GITEA_GITHUB_SYNC_REPOS = "${reposJson}";
        GIT_SSH_COMMAND = lib.concatStringsSep " " [
          "ssh"
          "-i ${credentialsDirectory}/ssh-key"
          "-o IdentitiesOnly=yes"
          # gitea's host key is pinned system-wide by programs.ssh.knownHosts.
          "-o StrictHostKeyChecking=yes"
        ];
        GIT_TERMINAL_PROMPT = "0";
        GIT_COMMITTER_NAME = cfg.committer.name;
        GIT_COMMITTER_EMAIL = cfg.committer.email;
        HOME = "/var/lib/gitea-github-sync";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        GIT_SSL_CAINFO = "/etc/ssl/certs/ca-certificates.crt";
      };
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        StateDirectory = "gitea-github-sync";
        StateDirectoryMode = "0700";
        LoadCredential = [ "ssh-key:${cfg.sshKeyFile}" ];
        ExecStart = lib.getExe gitea-github-sync;
        TimeoutStartSec = "30min";
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
    };

    systemd.timers.gitea-github-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
      };
    };
  };
}
