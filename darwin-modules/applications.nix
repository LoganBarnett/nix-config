{
  config,
  lib,
  pkgs,
  ...
}:

# Vendored from nix-darwin's modules/system/applications.nix (branch
# nix-darwin-25.11, rev ebec37af) to carry the timestamp and LaunchServices
# changes in the activation script ahead of an upstream pull request; see
# nix-darwin issue #1842.  Drop this module, and its disabledModules entry,
# once upstream carries the same behaviour.
{
  disabledModules = [ "system/applications.nix" ];

  config = {
    system.checks.text = lib.mkAfter ''
      ensureAppManagement() {
        for appBundle in /Applications/Nix\ Apps/*.app; do
          if [[ -d "$appBundle" ]]; then
            if ! touch "$appBundle/.DS_Store" &> /dev/null; then
              return 1
            fi
          fi
        done

        return 0
      }

      if ! ensureAppManagement; then
        if [[ "$(launchctl managername)" != Aqua ]]; then
          # It is possible to grant the App Management permission to `sshd-keygen-wrapper`, however
          # there are many pitfalls like requiring the primary user to grant the permission and to
          # be logged in when `darwin-rebuild` is run over SSH and it will still fail sometimes...
          printf >&2 '\e[1;31merror: permission denied when trying to update apps over SSH, aborting activation\e[0m\n'
          printf >&2 'Apps could not be updated as `darwin-rebuild` requires Full Disk Access to work over SSH.\n'
          printf >&2 'You can either:\n'
          printf >&2 '\n'
          printf >&2 '  grant Full Disk Access to all programs run over SSH\n'
          printf >&2 '\n'
          printf >&2 'or\n'
          printf >&2 '\n'
          printf >&2 '  run `darwin-rebuild` in a graphical session.\n'
          printf >&2 '\n'
          printf >&2 'The option "Allow full disk access for remote users" can be found by\n'
          printf >&2 'navigating to System Settings > General > Sharing > Remote Login\n'
          printf >&2 'and then pressing on the i icon next to the switch.\n'
          exit 1
        else
          # The TCC service required to modify notarised app bundles is `kTCCServiceSystemPolicyAppBundles`
          # and we can reset it to ensure the user gets another prompt
          tccutil reset SystemPolicyAppBundles > /dev/null

          if ! ensureAppManagement; then
            printf >&2 '\e[1;31merror: permission denied when trying to update apps, aborting activation\e[0m\n'
            printf >&2 '`darwin-rebuild` requires permission to update your apps, please accept the notification\n'
            printf >&2 'and grant the permission for your terminal emulator in System Settings.\n'
            printf >&2 '\n'
            printf >&2 'If you did not get a notification, you can navigate to System Settings > Privacy & Security > App Management.\n'
            exit 1
          fi
        fi
      fi
    '';

    system.build.applications = pkgs.buildEnv {
      name = "system-applications";
      paths = config.environment.systemPackages;
      pathsToLink = [ "/Applications" ];
    };

    system.activationScripts.applications.text = ''
      # Set up applications.
      echo "setting up /Applications/Nix Apps..." >&2

      ourLink () {
        local link
        link=$(readlink "$1")
        [ -L "$1" ] && [ "''${link#*-}" = 'system-applications/Applications' ]
      }

      ${lib.optionalString (config.system.primaryUser != null) ''
        # Clean up for links created at the old location in HOME
        # TODO: Remove this in 25.11.
        if ourLink ~${config.system.primaryUser}/Applications; then
          rm ~${config.system.primaryUser}/Applications
        elif ourLink ~${config.system.primaryUser}/Applications/'Nix Apps'; then
          rm ~${config.system.primaryUser}/Applications/'Nix Apps'
        fi
      ''}

      targetFolder='/Applications/Nix Apps'

      # Clean up old style symlink to nix store
      if [ -e "$targetFolder" ] && ourLink "$targetFolder"; then
        rm "$targetFolder"
      fi

      mkdir -p "$targetFolder"

      # Not --archive: that would also preserve timestamps, and the Nix store
      # normalizes every mtime to 1.  A bundle that keeps that mtime after
      # copying trips two problems.  macOS (observed on 26.3) can reject the
      # code signature of an app whose modification time is 1.  And
      # LaunchServices decides whether to rescan a bundle from the mtime of
      # the bundle's root directory, so a replaced Info.plist or executable
      # underneath an unchanged root is never noticed; its cached record keeps
      # serving the old plist, which can leave an app unlaunchable (a stale
      # LSEnvironment entry makes launches fail with permErr -54 until the
      # record is refreshed).
      rsyncFlags=(
        --recursive
        --links
        --perms
        # mtime is standardized in the nix store, which would leave only file size to distinguish files.
        # Thus we need checksums, despite the speed penalty.
        --checksum
        # Converts all symlinks pointing outside of the copied tree (thus unsafe) into real files and directories.
        # This neatly converts all the symlinks pointing to application bundles in the nix store into
        # real directories, without breaking any relative symlinks inside of application bundles.
        # This is good enough, because the make-symlinks-relative.sh setup hook converts all $out internal
        # symlinks to relative ones.
        --copy-unsafe-links
        --delete
        --chmod=-w
        # One line per created, changed or deleted path, so the bundles that
        # actually changed can be found below.
        --itemize-changes
      )

      # A command substitution rather than a pipe or process substitution, so
      # that a failing rsync still fails the activation.
      itemized=$(${lib.getExe pkgs.rsync} "''${rsyncFlags[@]}" ${config.system.build.applications}/Applications/ "$targetFolder")

      # Each itemized line is an eleven character change summary (or
      # "*deleting" padded to the same width), one space, then the path
      # relative to the target folder.  The first path component is the
      # bundle.
      declare -A changedBundles=()
      while IFS= read -r line; do
        item=''${line:12}
        bundle=''${item%%/*}
        case "$bundle" in
          *.app) changedBundles["$bundle"]=1 ;;
        esac
      done <<< "$itemized"

      # Bump the root mtime of every changed bundle so LaunchServices rescans
      # it on its next lookup, for every user.  Only the root counts: fresh
      # mtimes on the files underneath do not trigger a rescan.
      for bundle in "''${!changedBundles[@]}"; do
        if [ -d "$targetFolder/$bundle" ]; then
          touch "$targetFolder/$bundle"
        fi
      done

      # Bundles copied by earlier activations still carry the store's mtime
      # on their root, so give each of those a real mtime once.
      for appBundle in "$targetFolder"/*.app; do
        if [ -d "$appBundle" ] && [ "$(stat --format=%Y "$appBundle")" -le 1 ]; then
          touch "$appBundle"
        fi
      done
    '';
  };
}
