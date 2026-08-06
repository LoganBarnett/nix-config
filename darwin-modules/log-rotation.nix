################################################################################
# Scheduled log rotation for macOS, via logrotate.
#
# macOS offers no rotation for the logs our launchd jobs and scripts emit.
# launchd's StandardOutPath/StandardErrorPath are plain file descriptors
# opened at spawn — no size caps, no rotation.  The system rotator,
# newsyslog, rotates by renaming the file into place, and that breaks on
# every log we emit: the writers hold their descriptor for the life of the
# process.  launchd holds the StandardOutPath descriptor for as long as the
# job runs, and gpclient inherits monitor.log's descriptor from a shell `>>`
# redirect and holds it for the whole VPN session.  After a rename, a held
# descriptor still points at the old inode, so the disk space is never
# reclaimed and the output silently vanishes from the path being watched.
#
# logrotate's copytruncate policy fits these writers: copy the contents
# aside, compress the copy, and truncate the original in place.  Every
# holder writes through an append-mode descriptor (`>>` and launchd's log
# paths both open with O_APPEND), so the first write after truncation lands
# at offset zero — no sparse hole, no stranded descriptor.  The cost is the
# usual copytruncate caveat: bytes written between the copy and the truncate
# are lost.  For these diagnostic logs that trade is fine.
#
# Register a log by giving it a name and a path; everything else has
# defaults:
#
#   services.log-rotation.files.my-service.path = "/var/log/my-service.log";
#
# Files whose parent directory is owned by a user (e.g. logs under a home
# directory) additionally need that user declared.  logrotate runs as root
# and refuses to touch logs in non-root-owned directories unless told which
# identity to drop to (its `su` directive):
#
#   services.log-rotation.files.my-user-service = {
#     path = "/Users/alice/.local/share/my-service/log";
#     user = "alice";
#   };
#
# The rotation machinery activates whenever at least one file is registered;
# there is no separate enable switch.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.log-rotation;
  # logrotate's own run log, registered below so it is rotated like
  # everything else.  It stays tiny: logrotate is silent unless something
  # goes wrong.
  runLog = "/var/log/logrotate.log";
  renderStanza =
    name: f:
    let
      directives = [
        f.frequency
        "rotate ${toString f.keep}"
        "copytruncate"
        "compress"
        "missingok"
        "notifempty"
      ]
      ++ lib.optional (f.user != null) "su ${f.user} ${f.group}"
      ++ f.extraConfig;
    in
    ''
      # ${name}
      ${f.path} {
        ${lib.concatStringsSep "\n  " directives}
      }
    '';
  logrotateConf = pkgs.writeText "logrotate.conf" ''
    # Pin the compressor so rotation does not depend on PATH.
    compresscmd ${pkgs.gzip}/bin/gzip
    uncompresscmd ${pkgs.gzip}/bin/gunzip

    ${renderStanza "logrotate-self" {
      path = runLog;
      frequency = "daily";
      keep = 8;
      user = null;
      group = "staff";
      extraConfig = [ ];
    }}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList renderStanza cfg.files)}
  '';
in
{
  options.services.log-rotation = {
    files = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "Absolute path of the log file to rotate.";
            };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Owner of the log's parent directory, when that owner is not
                root.  Emitted as logrotate's `su` directive; without it,
                logrotate refuses to rotate logs living in a non-root-owned
                directory.
              '';
            };
            group = lib.mkOption {
              type = lib.types.str;
              default = "staff";
              description = "Group paired with `user` in the `su` directive.";
            };
            frequency = lib.mkOption {
              type = lib.types.enum [
                "daily"
                "weekly"
                "monthly"
              ];
              default = "daily";
              description = "How often to rotate.";
            };
            keep = lib.mkOption {
              type = lib.types.int;
              default = 8;
              description = "How many rotated (compressed) generations to keep.";
            };
            extraConfig = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional raw logrotate directives for this file.";
            };
          };
        }
      );
      default = { };
      description = "Log files to rotate, keyed by a short descriptive name.";
    };
  };

  config = lib.mkIf (cfg.files != { }) {
    launchd.daemons.logrotate = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.logrotate}/sbin/logrotate"
          "--state"
          "/var/db/logrotate.state"
          "${logrotateConf}"
        ];
        # Daily, in the small hours.  launchd coalesces a missed interval
        # (e.g. the machine was asleep at 03:17) into one run on wake, so
        # rotation still happens on laptops that sleep overnight.
        StartCalendarInterval = [
          {
            Hour = 3;
            Minute = 17;
          }
        ];
        RunAtLoad = false;
        StandardOutPath = runLog;
        StandardErrorPath = runLog;
      };
    };
  };
}
