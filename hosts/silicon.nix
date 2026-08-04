################################################################################
# This defines the entirety of the configuration for the silicon host.
################################################################################
{
  config,
  facts,
  lib,
  flake-inputs,
  host-id,
  pkgs,
  system,
  ...
}:
let
in
{
  imports = [
    ../nixos-configs/acme.nix
    ../nixos-configs/alertmanager.nix
    ../nixos-configs/alertmanager-alerts.nix
    ../hardware/aeotec-z-stick-7.nix
    ../nixos-configs/openhab.nix
    ../nixos-configs/zwave-js-ui.nix
    ../nixos-configs/org-wiki.nix
    ../nixos-configs/dhcp-lease-textfile.nix
    ../nixos-configs/chronicle-proxy.nix
    ../nixos-configs/gitea.nix
    ../nixos-configs/gitea-deployment-webhooks.nix
    ../nixos-configs/garage-queue-server.nix
    ../nixos-modules/nextcloud.nix
    ../nixos-configs/notes-sync.nix
    ../nixos-configs/ntfy.nix
    ../nixos-configs/dns-server.nix
    ../nixos-configs/dns-smart-block.nix
    ../nixos-configs/unbound.nix
    ../nixos-modules/grafana.nix
    ../nixos-modules/makemkv-ripper.nix
    ../nixos-modules/makemkv-updater.nix
    ../nixos-modules/makemkv-keydb-updater.nix
    ../nixos-configs/matrix-server.nix
    ../nixos-configs/nfs-mount-provider-from-facts.nix
    ../nixos-configs/openldap-facts.nix
    ../nixos-modules/prometheus-server.nix
    ../nixos-configs/loku.nix
    ../nixos-configs/authelia.nix
    ../nixos-configs/freeradius.nix
    ../nixos-configs/ruckus-48zp-switch.nix
    ../nixos-configs/immich.nix
    ../nixos-configs/ivatar.nix
    ../nixos-configs/mastodon.nix
    ../nixos-configs/metube.nix
    ../nixos-configs/porkbun-dns-email.nix
    ../nixos-configs/porkbun-dns.nix
    ../nixos-configs/sftpgo.nix
    ../nixos-modules/stalwart.nix
    ../nixos-configs/stalwart.nix
    ../nixos-configs/sonify-health-silicon.nix
    ../nixos-configs/sonify-health-goss.nix
    ../nixos-configs/nix-builder-provide.nix
    ../nixos-modules/linux-host.nix
    # TODO: Right now agenix-rekey wants to build wireguard to do the
    # generation.  This fails due to a problem with macOS building wireguard-go
    # (documented in the overlay in this repository).  It is not understood why
    # it's not using the overlays.  I've removed the root nixpkgs channel and it
    # still provides this error, even with all the settings see in
    # ../nixos-modules/nix-flake-environment.nix.  I'm at a loss here.  This
    # probably warrants a ticket and I'll get to that sometime.  I have
    # confirmed that commenting this out (at least temporarily) fixes the issue.
    # However I already have pre-generated secrets so I'm not bumping into the
    # issue currently.
    ../nixos-configs/silicon-public.nix
    # Enable to make this host the network gateway (VLANs, NAT, inter-VLAN
    # firewall).  Disable to use the consumer router as the gateway.
    # ../nixos-configs/network-gateway.nix
    ../nixos-configs/wireguard/server-standard.nix
    (
      { pkgs, ... }:
      {
        # networking.hostId is needed by the filesystem stuffs.
        # An arbitrary ID needed for zfs so a pool isn't accidentally imported on
        # a wrong machine (I'm not even sure what that means).  See
        # https://search.nixos.org/options?channel=24.05&show=networking.hostId&from=0&size=50&sort=relevance&type=packages&query=networking.hostId
        # for docs.
        # Get from an existing machine using:
        # head -c 8 /etc/machine-id
        # Generate for a new machine using:
        # head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
        networking.hostId = "d88d6477";
        nixpkgs.hostPlatform = system;
      }
    )
    # Silicon has a main disk for the OS, and then two disks for data.   One for
    # the primary data and one as an incremental backup.
    {
      imports = [
        flake-inputs.disko.nixosModules.default
      ];
      # Very relevant to disko configuration, since not having these settings
      # will cause the grub installation to fail.
      # boot.loader.systemd-boot.enable = true;
      boot.loader.systemd-boot.enable = false;
      # boot.loader.efi.canTouchEfiVariables = true;
      # boot.loader.grub = {
      #   device = "nodev";
      #   efiSupport = true;
      #   # efiInstallAsRemovable = true;
      # };
      boot.loader.grub = {
        enable = true;
        # devices = [ "/dev/disk/by-id/ata-WDC_WD80EAAZ-00BXBB0_WD-RD2G0Z2H" ];
        # device = "/dev/disk/by-id/ata-WDC_WD80EAAZ-00BXBB0_WD-RD2G0Z2H";
        # device = "nodev";
        devices = [ "nodev" ];
        # Force it to respect the device declaration sibling to this.
        # forceInstall = true;
        efiSupport = false;
      };
      disko.devices = {
        disk = {
          os = {
            type = "disk";
            device = "/dev/disk/by-id/ata-WDC_WDS100T2B0A-00SM50_200616A00BEF";
            content = {
              type = "gpt";
              efiGptPartitionFirst = false;
              partitions = {
                grub = {
                  size = "1M";
                  # BIOS boot partition.
                  type = "EF02";
                  # Lowest.
                  priority = 0;
                };
                boot = {
                  size = "512M";
                  # Linux filesystem.
                  type = "8300";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/boot";
                  };
                };
                # Hybrid support, in case we want to try UEFI again.
                # ESP = {
                #   size = "1G";
                #   type = "EF00";
                #   content = {
                #     type = "filesystem";
                #     format = "vfat";
                #     mountpoint = "/boot";
                #     mountOptions = [ "umask=0077" ];
                #   };
                # };
                root = {
                  size = "100%";
                  content = {
                    type = "filesystem";
                    format = "btrfs";
                    mountpoint = "/";
                  };
                };
              };
            };
          };
          data = {
            type = "disk";
            device = "/dev/disk/by-id/ata-WDC_WD80EAAZ-00BXBB0_WD-RD2G0Z2H";
            content = {
              type = "gpt";
              partitions = {
                data = {
                  size = "100%";
                  content = {
                    type = "lvm_pv";
                    vg = "vgData";
                  };
                };
              };
            };
          };
          backup = {
            type = "disk";
            device = "/dev/disk/by-id/ata-WDC_WD80EAAZ-00BXBB0_WD-RD2EW11H";
            content = {
              type = "gpt";
              partitions = {
                backup = {
                  size = "100%";
                  content = {
                    type = "lvm_pv";
                    vg = "vgBackup";
                  };
                };
              };
            };
          };
        };
        lvm_vg = {
          vgData = {
            type = "lvm_vg";
            lvs = {
              lvData = {
                size = "100%FREE";
                content = {
                  type = "filesystem";
                  format = "btrfs";
                  mountpoint = "/tank/data";
                };
              };
            };
          };
          vgBackup = {
            type = "lvm_vg";
            lvs = {
              lvBackup = {
                size = "100%FREE";
                content = {
                  type = "filesystem";
                  format = "btrfs";
                  mountpoint = "/tank/backup";
                };
              };
            };
          };
        };
      };
    }
  ];

  # Add secondary IPs from facts.network.hosts.silicon.extraAddresses to the
  # physical NIC.  dhcp-server.nix contributes the primary /24 address (.9) on
  # all possible interface name variants; mirror that approach here so the
  # secondary /32 addresses land on whichever name the kernel actually assigns.
  # NixOS merges list attributes across modules, so all addresses coexist.
  networking.interfaces =
    lib.genAttrs
      [
        "enp3s0"
        "eno1"
        "end0"
        "ens0"
        "eth0"
      ]
      (_: {
        ipv4.addresses = builtins.map (ipv4: {
          address = "${facts.network.subnets.barnett-main}.${toString ipv4}";
          prefixLength = 32;
        }) (builtins.attrValues facts.network.hosts.silicon.extraAddresses);
      });

  # Rename the Intel quad NIC port cabled to the provisioning switch.
  #
  # Kernel names like enp4s0f0 encode PCI bus/slot topology, so they are stable
  # only while the card stays in the slot it is in — reseat it, or move it from
  # the x4 to the x16, and the bus number changes and every name with it.  The
  # MAC is stamped on the card and does not move, so match on that instead and
  # give the port a name that says what it is for.
  #
  # Identified empirically: with the switch cabled and all four ports brought
  # up, only 00:15:17:74:2f:d0 showed carrier (1000 Mbps full duplex).  The
  # full set, since the jacks are *not* necessarily ordered left-to-right on
  # the bracket:
  #
  #   00:15:17:74:2f:d0     00:15:17:74:2f:d2
  #   00:15:17:74:2f:d1     00:15:17:74:2f:d3
  #
  # To re-identify, `ip link set <iface> up` on all four first — carrier reads
  # EINVAL on an admin-down interface, which looks exactly like a dead cable
  # and will send you chasing the wrong thing.
  systemd.network.links."10-provision0" = {
    matchConfig.MACAddress = "00:15:17:74:2f:d0";
    linkConfig.Name = "provision0";
  };

  # Meraki AP provisioning segment.
  #
  # The firmware manifest is pinned by SHA-256 but fetched at runtime, so none
  # of these URLs can block a rebuild.  Checksums: OpenWrt's are from the
  # release's published sha256sums; the u-boot ones are from the
  # openwrt-cryptid README.  That repo is pinned to a branch rather than a
  # commit, so a force-push upstream would trip the checksum and fail the fetch
  # loudly — which is the intended behaviour, not a gap.
  services.meraki-provisioning = {
    enable = true;
    interface = "provision0";
    firmware = {
      # Fetched over TFTP by the Meraki diagnostic firmware, then written to
      # the u-boot partition.  This is the irreversible step.
      "mr42_u-boot.mbn" = {
        url = "https://raw.githubusercontent.com/clayface/openwrt-cryptid/master/mr42_u-boot.mbn";
        sha256 = "ac39dcfb396b2fb115d8890ff812b51c0ff608b77cd3947c4d1f99aaf855a7ac";
      };
      # Only needed for the UART fallback path, via ubootwrite.py.
      "mr42_u-boot.bin" = {
        url = "https://raw.githubusercontent.com/clayface/openwrt-cryptid/master/mr42_u-boot.bin";
        sha256 = "319742c4baac6a8506b0ab2fd69b2927c0ef8f6f0d96c744388101ad7f62c53b";
      };
      # Deliberately clayface's build rather than a current OpenWrt release,
      # and this is load-bearing.  The 25.12.5 initramfs transferred completely
      # and was ACKed block for block — silicon's counters showed the full
      # 11125524 bytes out with a matching ACK count — and then simply never
      # booted.  u-boot's `bootbk` is a vendor command with a fixed load
      # address and a FIT layout expectation, and a 2026-built image is
      # evidently not what it wants.  The device fell through to
      # `bootbk 0x48000000 bootkernel2` and came up in stock Meraki firmware,
      # which is the designed failure path and cost nothing.
      #
      # This image is the one the flashing procedure was actually validated
      # against, and the repo already publishes it under exactly the
      # unversioned name u-boot's `fit_uimage_initramfs` asks for.
      #
      # The initramfs is only a vehicle to reach a shell — the release that
      # ends up installed comes from the sysupgrade image below, so the two
      # deliberately do not match.
      "openwrt-ipq806x-generic-meraki_mr42-initramfs-fit-uImage.itb" = {
        url = "https://raw.githubusercontent.com/clayface/openwrt-cryptid/master/openwrt-ipq806x-generic-meraki_mr42-initramfs-fit-uImage.itb";
        sha256 = "861e57593a207afbc26c2c2df2b8deb838b413af006b23e9f6142922fc9ed722";
      };
      # Pulled over HTTP from the booted initramfs, not by u-boot, so the
      # versioned name is fine and preferable.
      "openwrt-25.12.5-ipq806x-generic-meraki_mr42-squashfs-sysupgrade.bin" = {
        url = "https://downloads.openwrt.org/releases/25.12.5/targets/ipq806x/generic/openwrt-25.12.5-ipq806x-generic-meraki_mr42-squashfs-sysupgrade.bin";
        sha256 = "c0c4c529997552b32e62357c1cdb097ae3cd74e4d208a7bdd81c9676a7ab6967";
      };
    };
  };

  # Configure ACLs for shared media directory so both nextcloud and kodi can
  # read/write.
  systemd.services.setup-shared-media-acls = {
    description = "Set up ACLs for shared media directory";
    wantedBy = [ "multi-user.target" ];
    after = [ "tank-data.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.acl}/bin/setfacl -d -m g:media-shared:rwx /tank/data/nextcloud-shared-media
      ${pkgs.acl}/bin/setfacl -m g:media-shared:rwx /tank/data/nextcloud-shared-media
    '';
  };

  # Create and configure the shared media directory before Metube starts.
  systemd.services.setup-media-dir = {
    description = "Create and set ACLs for shared media directory";
    wantedBy = [ "multi-user.target" ];
    after = [ "tank-data.mount" ];
    requires = [ "tank-data.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /tank/data/media
      ${pkgs.acl}/bin/setfacl -d -m g:media-shared:rwx /tank/data/media
      ${pkgs.acl}/bin/setfacl -m g:media-shared:rwx /tank/data/media
    '';
  };

  # Btrfs deduplication for /tank/data only. Runs weekly to reclaim space from
  # duplicate files (e.g., photos re-uploaded by phones).
  environment.systemPackages = [ pkgs.duperemove ];

  systemd.services.duperemove-tank-data = {
    description = "Deduplicate files on /tank/data using duperemove";
    after = [ "tank-data.mount" ];
    serviceConfig = {
      Type = "oneshot";
      # Run with lower priority to avoid impacting other services.
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = ''
      ${pkgs.duperemove}/bin/duperemove \
        -r \
        -d \
        --dedupe-options=same \
        --hashfile=/tank/data/.duperemove.hash \
        -h \
        /tank/data
    '';
  };

  systemd.timers.duperemove-tank-data = {
    description = "Weekly deduplication of /tank/data";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Run Sundays at 02:00 UTC (before the 11:00 UTC / 03:00 PST backup).
      OnCalendar = "Sun *-*-* 02:00:00";
      Persistent = true;
    };
  };

  # Allow the physical eject button to open the optical drive tray.
  hardware.opticalDrive.lockDoor = false;

  # MakeMKV DVD ripper for Silicon's internal drive.
  services.makemkv-ripper = {
    enable = true;
    outputPath = "/tank/data/kodi-media";
    autoRip = true;
    ejectWhenComplete = true;
    outputUser = "root";
    outputGroup = "media-shared";
    defaultDevice = "/dev/sr0";
  };

  # Auto-update MakeMKV beta key monthly.
  services.makemkv-updater = {
    enable = true;
    user = "root";
    group = "root";
  };

  # Auto-update MakeMKV AACS key database monthly.
  services.makemkv-keydb-updater = {
    enable = true;
    user = "root";
    group = "root";
  };

  # Terminal kiosk on tty1 — shows btop on a dedicated monitor.
  services.terminal-kiosk = {
    enable = true;
    programs = [
      {
        name = "btop";
        command = "${pkgs.btop}/bin/btop";
      }
    ];
  };

  # Silicon provides builds to other hosts, so it should not consume builds
  # from itself.  Override the nix-builder-consume module imported by
  # linux-host.nix to prevent self-referential build loops.
  networking.monitors = [ "goss" ];
  nix.distributedBuilds = lib.mkForce false;
  nix.buildMachines = lib.mkForce [ ];
}
