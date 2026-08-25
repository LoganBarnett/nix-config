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

  # Ask diskutil directly for external, physical whole disks.  This covers
  # every bus (USB, Thunderbolt, built-in card readers) and by construction
  # excludes internal disks, partition entries, and virtual disks such as
  # mounted disk images.
  #
  # diskutil's -plist and plutil's -convert and -o flags have no long-form
  # equivalents.
  json="$(
    diskutil list -plist external physical \
      | plutil -convert json -o - -
  )"
  count="$(${pkgs.jq}/bin/jq '.WholeDisks | length' <<<"$json")"
  if [[ "$count" != 1 ]]; then
    disks="$(
      ${pkgs.jq}/bin/jq --raw-output '.WholeDisks | join(", ")' <<<"$json"
    )"
    echo "Error: Query result [$disks] has $count results but we expect exactly 1." 1>&2
    exit 1
  else
    ${pkgs.jq}/bin/jq --raw-output --join-output '.WholeDisks[0]' <<<"$json"
  fi
''
