{ pkgs }:
pkgs.writeShellScriptBin "disk-detachable" ''
  ##
  # Finds the device file for the attached SD card (eg. /dev/disk4) or USB
  # drive.  It will assume /dev as a relative directory to make consumption
  # easier.
  #
  # This has a non-zero exit code if more than one disk is found, or no disks
  # are found.
  ##

  set -euo pipefail

  while true; do
    case "''${1:-}" in
      -h | --help)
        printf '%s\n' \
          "Usage: $0" \
          "" \
          "Finds the device file for the attached SD card (eg. /dev/disk4) or USB drive." \
          "It will assume /dev as a relative directory to make consumption easier."
        exit
        ;;
      * ) break ;;
    esac
  done

  if [[ "$(uname -s)" == 'Darwin' ]]; then
    # Ask diskutil directly for external, physical whole disks.  This covers
    # every bus (USB, Thunderbolt, built-in card readers) and by construction
    # excludes internal disks, partition entries, and virtual disks such as
    # mounted disk images.
    #
    # diskutil's -plist and plutil's -convert and -o flags have no long-form
    # equivalents.
    disks="$(
      diskutil list -plist external physical \
        | plutil -convert json -o - - \
        | ${pkgs.jq}/bin/jq '.WholeDisks'
    )"
  else
    # HOTPLUG covers removable media and hotplug buses such as USB, which is
    # the closest match to diskutil's "external physical".  util-linux older
    # than 2.37 emits "1" strings rather than JSON booleans.
    disks="$(
      lsblk --json --nodeps --output NAME,TYPE,HOTPLUG \
        | ${pkgs.jq}/bin/jq '[
            .blockdevices[]
            | select(.type == "disk" and (.hotplug == true or .hotplug == "1"))
            | .name
          ]'
    )"
  fi
  count="$(${pkgs.jq}/bin/jq 'length' <<<"$disks")"
  if [[ "$count" != 1 ]]; then
    names="$(${pkgs.jq}/bin/jq --raw-output 'join(", ")' <<<"$disks")"
    echo "Error: Query result [$names] has $count results but we expect exactly 1." 1>&2
    exit 1
  else
    ${pkgs.jq}/bin/jq --raw-output --join-output '.[0]' <<<"$disks"
  fi
''
