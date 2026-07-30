################################################################################
# Cisco Meraki access point provisioning network.
#
# Serves the files needed to flash OpenWrt onto Cisco Meraki access points, on
# an isolated, unrouted segment that exists only for that purpose.
#
# Deliberately Meraki-specific rather than a generic AP provisioning module.
# Everything load-bearing here — the 192.168.1.250 server address, the
# unversioned initramfs filename, the u-boot-over-TFTP sequence — comes from
# the replacement u-boot that Meraki hardware gets flashed with.  Another
# vendor's AP will not use this mechanism, and pretending otherwise would
# invite someone to generalise a module whose constants are not general.
#
# See the OpenWrt MR42 device page for the flashing procedure itself:
# https://openwrt.org/toh/meraki/mr42
#
# WHY 192.168.1.0/24, AND WHY THE ADDRESS IS NOT NEGOTIABLE
# ─────────────────────────────────────────────────────────
# The replacement u-boot flashed onto the MR42 carries a compiled-in default
# environment.  Extracted from the image itself:
#
#   ipaddr=192.168.1.100
#   serverip=192.168.1.250
#   bootdelay=2
#   bootcmd=tftpboot $fit_uimage_initramfs; bootbk 0x48000000 bootkernel2 $config_dts
#   fit_uimage_initramfs=openwrt-ipq806x-generic-meraki_mr42-initramfs-fit-uImage.itb
#
# So the AP *will* ask 192.168.1.250 for a file with that exact, unversioned
# name.  Neither address nor filename is configurable without either rebuilding
# u-boot or interrupting the 2 second bootdelay over a serial console.  The
# firmware manifest below therefore renames the versioned OpenWrt download to
# the name u-boot expects.
#
# This subnet is free on our network (we run 192.168.254.0/24), so this exists
# as a standing provisioning segment rather than something stood up per-flash.
# Every future AP wants the same thing, and the u-boot hardcoding is never
# going to change.
#
# WHY BOTH TFTP AND HTTP
# ──────────────────────
# TFTP is mandatory: u-boot speaks nothing else, and it is what fetches
# mr42_u-boot.mbn and the initramfs.  HTTP is a convenience for the second
# half — once the initramfs has booted, pulling the sysupgrade image with wget
# beats scp'ing it in.
#
# WHY PLAIN HTTP AND NOT TLS
# ──────────────────────────
# TLS is actively counterproductive here, for four independent reasons:
#
#   1. The AP has no clock.  It boots at the epoch or at its build date, so
#      certificate validity windows fail — the same class of failure that took
#      silicon's DNS down when its CMOS battery died.
#   2. The AP has no resolver on this segment, so it connects by IP.  That is a
#      name mismatch unless the certificate carries an IP SAN.
#   3. The stock OpenWrt initramfs may lack ca-bundle and libustream-ssl, and
#      installing them needs working network access — which is circular.
#   4. The segment is unrouted and holds exactly one device at a time.
#
# Integrity is enforced where it actually belongs: the fetch unit below
# verifies a SHA-256 pinned in this file before any byte is served.  That is a
# stronger guarantee than transport encryption would give us, because it also
# covers the upstream host being compromised.
#
# WHY FIRMWARE IS FETCHED AT RUNTIME RATHER THAN BAKED INTO THE STORE
# ───────────────────────────────────────────────────────────────────
# A fetchurl in the store would make every `nixos-rebuild` on this host depend
# on GitHub and downloads.openwrt.org being reachable.  That is an unacceptable
# coupling for a rarely-used provisioning path — a firmware mirror outage must
# never be able to block an unrelated deploy.
#
# So: hashes live in the Nix store, bytes live on disk.  The manifest is
# declarative and pinned; the download is a timer-driven oneshot that retries
# on its own and is wired into nothing.  If it fails, nothing else does.
################################################################################
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.meraki-provisioning;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  firmware-type = types.submodule (
    { name, ... }:
    {
      options = {
        filename = mkOption {
          type = types.str;
          default = name;
          description = ''
            Name the file is served as.  Defaults to the attribute name.  This
            is deliberately independent of the URL's basename, because u-boot
            demands an unversioned initramfs filename while OpenWrt publishes a
            versioned one.
          '';
        };
        url = mkOption {
          type = types.str;
          description = "Where to fetch the file from.";
        };
        sha256 = mkOption {
          type = types.str;
          description = ''
            Lowercase hex SHA-256 of the file.  Verified after download and
            re-verified on every timer run, so upstream substituting the file
            fails loudly instead of silently serving something else to an AP
            we are about to overwrite the bootloader on.
          '';
        };
      };
    }
  );

  # Emits the download-and-verify shell.  Kept out of the unit definition so
  # the escaping stays legible.
  fetch-script = pkgs.writeShellApplication {
    name = "meraki-provisioning-fetch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
    ];
    text = ''
      root=${lib.escapeShellArg cfg.stateDir}
      install --directory --mode=0755 "$root"
      rc=0

      # One function called per file, rather than inlining a block per file.
      # The generated calls sit at top level, so an inlined block could not use
      # `continue` to skip a failure — there is no enclosing loop — and under
      # writeShellApplication's `set -e` that would abort the whole run on the
      # first bad mirror instead of trying the rest.
      fetch_one() {
        local filename="$1" url="$2" want="$3"
        local dest="$root/$filename"
        local tmp="$dest.partial"
        local got

        # Re-verify what is already on disk rather than trusting its presence.
        # Cheap, and it catches bit-rot and hand-edits as well as a changed
        # upstream.
        if [ -f "$dest" ] \
          && [ "$(sha256sum "$dest" | cut --delimiter=" " --fields=1)" = "$want" ]; then
          echo "ok (cached): $filename"
          return 0
        fi

        echo "fetching: $filename"
        rm --force "$tmp"
        if ! curl --location --fail --silent --show-error \
                  --retry 3 --retry-delay 5 --max-time 600 \
                  --output "$tmp" "$url"; then
          echo "FAILED to download $filename" >&2
          rm --force "$tmp"
          return 1
        fi

        got=$(sha256sum "$tmp" | cut --delimiter=" " --fields=1)
        if [ "$got" != "$want" ]; then
          echo "CHECKSUM MISMATCH for $filename: want $want, got $got" >&2
          rm --force "$tmp"
          return 1
        fi

        # Rename only after verification, so a partial or wrong file is never
        # visible to TFTP or nginx even momentarily.
        chmod 0644 "$tmp"
        mv --force "$tmp" "$dest"
        echo "ok (fetched): $filename"
      }

      # `|| rc=1` rather than letting a failure propagate: one unreachable
      # mirror should not stop us fetching everything else, but the unit should
      # still end up failed so the timer retries it.
      ${lib.concatMapStringsSep "\n" (f: ''
        fetch_one ${lib.escapeShellArg f.filename} ${lib.escapeShellArg f.url} \
          ${lib.escapeShellArg f.sha256} || rc=1
      '') (lib.attrValues cfg.firmware)}
      exit "$rc"
    '';
  };
in
{
  options.services.meraki-provisioning = {
    enable = mkEnableOption "the Cisco Meraki AP provisioning network and file server";

    interface = mkOption {
      type = types.str;
      example = "enp4s0f0";
      description = ''
        Physical interface carrying the provisioning segment.  This must be a
        plain untagged link — u-boot does not speak 802.1Q, so the AP's switch
        port has to be an access port and this end cannot be a VLAN
        sub-interface.
      '';
    };

    address = mkOption {
      type = types.str;
      default = "192.168.1.250";
      description = ''
        Address to serve from.  Changing this breaks TFTP boot: it is compiled
        into the replacement u-boot as `serverip` and cannot be overridden
        without a serial console.
      '';
    };

    prefixLength = mkOption {
      type = types.ints.between 1 32;
      default = 24;
      description = ''
        Must cover 192.168.1.100, which the AP assigns itself from the same
        compiled-in u-boot environment.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/meraki-provisioning";
      description = "Where fetched firmware lives and what both servers serve.";
    };

    firmware = mkOption {
      type = types.attrsOf firmware-type;
      default = { };
      description = ''
        Files to fetch and serve, keyed by served filename.  Empty by default
        so enabling the segment does not imply any particular AP model.
      '';
    };
  };

  config = mkIf cfg.enable {
    # No gateway and no route off this segment.  It reaches silicon and nothing
    # else, which is the entire point.
    networking.interfaces.${cfg.interface}.ipv4.addresses = [
      {
        address = cfg.address;
        prefixLength = cfg.prefixLength;
      }
    ];

    # Scoped to the provisioning interface so neither server is exposed to the
    # real network.  TFTP replies leave from an ephemeral source port, but that
    # is silicon's outbound direction and unfiltered, so opening 69 inbound is
    # sufficient.
    networking.firewall.interfaces.${cfg.interface} = {
      allowedUDPPorts = [ 69 ];
      allowedTCPPorts = [ 80 ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root -"
    ];

    # Deliberately not wantedBy any target.  The timer owns this, so a mirror
    # outage cannot leave the host permanently degraded — the next run clears
    # it.
    systemd.services.meraki-provisioning-fetch = {
      description = "Fetch and verify access point firmware images";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe fetch-script;
      };
    };

    systemd.timers.meraki-provisioning-fetch = {
      description = "Periodically refresh access point firmware images";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1d";
        # Catch up after downtime rather than waiting a full day.
        Persistent = true;
      };
    };

    # u-boot's only transport.  Bound to the provisioning address so this is
    # not answering on the production network.
    services.atftpd = {
      enable = true;
      root = cfg.stateDir;
      extraOptions = [ "--bind-address ${cfg.address}" ];
    };

    # HTTP for the sysupgrade fetch from the booted initramfs.  Declared as the
    # default server on this address rather than by name, because the AP has no
    # resolver here and connects by IP — there is no useful Host header to
    # match on.  autoindex is on so you can eyeball what is actually available
    # from the AP's shell before committing to a sysupgrade.
    services.nginx = {
      enable = true;
      virtualHosts.meraki-provisioning = {
        default = true;
        listen = [
          {
            addr = cfg.address;
            port = 80;
            ssl = false;
          }
        ];
        root = cfg.stateDir;
        locations."/".extraConfig = ''
          autoindex on;
        '';
      };
    };
  };
}
