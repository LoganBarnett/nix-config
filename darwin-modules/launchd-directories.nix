################################################################################
# Adds launchd.daemons.<name>.directories, the directories a daemon needs to
# exist with a given owner and mode before it starts.  launchd has no equivalent
# of systemd's tmpfiles or StateDirectory.  The directories are created during
# activation, after users and groups exist and before any plist is loaded.
# Activation does not run at boot, so this suits paths that persist across
# reboots such as /var/lib.  A path under /var/run is wiped at boot and needs a
# start wrapper instead.  See dns-c-ares-scopeless-fix.nix for that pattern.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  directorySubmodule = lib.types.submodule {
    options = {
      owner = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "Owner of the directory.";
      };
      group = lib.mkOption {
        type = lib.types.str;
        default = "wheel";
        description = "Group of the directory.";
      };
      mode = lib.mkOption {
        type = lib.types.strMatching "[0-7]{3,4}";
        default = "0755";
        description = "Octal mode of the directory.";
      };
    };
  };
  entries = lib.concatMap (
    daemon:
    lib.mapAttrsToList (path: dir: {
      inherit path;
      inherit (dir) owner group mode;
    }) daemon.directories
  ) (lib.attrValues config.launchd.daemons);
  # install creates missing parents, re-applies owner and mode to a directory
  # that already exists, and leaves its contents alone.
  installLine =
    entry:
    lib.concatStringsSep " " [
      "${pkgs.coreutils}/bin/install"
      "--directory"
      "--owner ${lib.escapeShellArg entry.owner}"
      "--group ${lib.escapeShellArg entry.group}"
      "--mode ${entry.mode}"
      (lib.escapeShellArg entry.path)
    ];
in
{
  options.launchd.daemons = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.directories = lib.mkOption {
          type = lib.types.attrsOf directorySubmodule;
          default = { };
          description = ''
            Directories created with this owner and mode during activation,
            after users and groups exist and before any plist is loaded.
            Keyed by absolute path.  Activation does not run at boot, so this
            suits paths that persist across reboots.  A path under /var/run
            is wiped at boot and needs a start wrapper instead.
          '';
        };
      }
    );
  };

  config = lib.mkIf (entries != [ ]) {
    # The name launchd is required by nix-darwin.  Its activate script runs a
    # fixed list of activation script names, and any other name is accepted
    # by the option type and silently ignored.  launchd is the only slot
    # ordered after users and groups are created and before plists are
    # loaded.  mkBefore puts these lines ahead of the plist loop.
    system.activationScripts.launchd.text = lib.mkBefore (
      lib.concatMapStringsSep "\n" installLine entries
    );
  };
}
