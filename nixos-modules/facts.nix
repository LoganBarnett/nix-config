################################################################################
# I've other people use the nomenclature of "facts", and it kind of makes sense
# because "settings" would be a very ambiguous term.  "Facts" is only de facto
# via Puppet, as I understand.
#
# It means settings, but more like a meta settings.  Settings here should be
# logical instead of pertaining to specific systems whenever possible.
################################################################################
{
  network = rec {
    # I have a naming theme of periodic elements and particles.
    domain = "proton";
    # The host-id of the machine that serves DNS for the home network.  Used
    # by pkgs.lib.custom.networkDnsIp to derive the server's full IP address.
    dns-host = "silicon";
    # The host-id of the machine acting as the network's default gateway
    # (router).  vpn-reconcile reads this host's macAddresses (via
    # pkgs.lib.custom.networkGatewayMacs) to recognize the home network at L2,
    # independent of the VPN tunnel's state.  Currently the consumer router;
    # flip to "silicon" when network-gateway.nix is enabled there (its MAC is
    # already recorded).
    gateway-host = "gateway";
    # These are just stringly prefixes for IP addresses.  At some point I should
    # turn these into real subnets with masks.
    subnets = {
      # The main network, whose atypical subnet is a vestigial dictation by the
      # consumer router.
      barnett-main = "192.168.254";
      # IoT VLAN (20) — isolated devices with per-device internet allowlisting.
      barnett-iot = "10.20.0";
      # Guest VLAN (30) — internet-only access, no internal LAN visibility.
      barnett-guest = "10.30.0";
    };
    # The VLAN plan.  The rule: VLAN N owns the 10.N.0.0/16 allocation,
    # deployed as a /24 until a segment needs more, at which point the mask
    # widens in place — no renumbering.  Names are roles, not sites: the
    # geode direction is a core codebase any household network can
    # instantiate, so nothing here may carry a family or site name.  The
    # gateway host owns .1 on every VLAN it routes; legacy predates that
    # convention and dies rather than adopt it.  VLAN 100 is reserved for
    # the wan uplink (no internal subnet; see network-gateway.nix).  These
    # supersede the stringly `subnets` above, which remain for incremental
    # migration.
    vlans = {
      # Trusted — admitted, full-permission devices.
      main = {
        id = 10;
        prefix = "10.10.0";
        prefixLength = 24;
      };
      # IoT — blocked by default, per-device internet allowlisting.
      iot = {
        id = 20;
        prefix = "10.20.0";
        prefixLength = 24;
      };
      # Guest — internet-only, no internal LAN visibility.
      guest = {
        id = 30;
        prefix = "10.30.0";
        prefixLength = 24;
      };
      # Onboarding lobby — reaches only the gateway's enrollment services.
      lobby = {
        id = 40;
        prefix = "10.40.0";
        prefixLength = 24;
      };
      # In-band management for network gear (APs).  The physical
      # out-of-band link to the switch holds 10.99.0.0/24; this is the
      # sibling /24 within the same "99 means management" allocation.
      mgmt = {
        id = 99;
        prefix = "10.99.1";
        prefixLength = 24;
      };
      # The old mixed-trust network, unchanged while the admission flow
      # drains it device by device.  254 matches 192.168.254 mnemonically
      # and marks itself terminal.
      legacy = {
        id = 254;
        prefix = "192.168.254";
        prefixLength = 24;
      };
    };
    ##
    # The nfsVolumes here have the following structure:
    # {
    #   host-id = "oganesson";
    #   peerNumber = 118;
    #   volume = "photos";
    # };
    #
    # - The hostname is the hostname portion of the host's FQDN.
    # - peerNumber is used to build the host's IP used in the WireGuard network
    #   used to secure the NFS shares.
    # - volume is the name of the volume to share, which will expand to
    #   "/tank/data/${volume}".
    nfsVolumes = [
      {
        consumerHostId = "krypton";
        providerHostId = "silicon";
        peerNumber = 4;
        service = "media-shared";
        volume = "kodi-media";
        user = "kodi";
        group = "media-shared";
        gid = 29974;
        backupContents = true;
      }
      {
        consumerHostId = "krypton";
        providerHostId = "silicon";
        peerNumber = 4;
        service = "media-shared";
        volume = "nextcloud-shared-media";
        user = "kodi";
        group = "media-shared";
        gid = 29974;
        backupContents = false;
      }
    ];
    ##
    # The hosts here have the following structure:
    # "${hostname}" = {
    #  controlledHost = boolean;
    #  expectedOnline = boolean;
    #  flake-input-overrides = {
    #    nixpkgs = "nixpkgs-some-pr-or-variant";
    #  };
    #  ipv4 = 123;
    #  monitors = [
    #    "node"
    #    "systemd"
    #  ];
    #  roaming = boolean;
    #  system = "aarch64-linux";
    # };
    #
    # - The hostname is the hostname portion of the host's FQDN.
    # - controlledHost indicates this is a host that is controlled completely by
    #   our configuration here.  This can have many implications.  A
    #   non-controlled host being monitored will be the target of a ping, for
    #   example.
    # - flake-input-overrides (optional) allows remapping one of the flake
    #   inputs to override another.  A common case for this is to override
    #   nixpkgs, but could be used for any combination of inputs.  The key is
    #   the name if the input to override, and the value is a String that
    #   matches the key from flake-inputs to substitute.
    # - ipv4 The host portion of this host's IP address.  This will be fixed in
    #   the DNS.  Leaving this out means the host uses DHCP.  Alternatively it
    #   means we're talking about a container.
    # - monitors (optional) A list of monitors for non-Nix-managed hosts.
    #   Nix-managed hosts declare monitors via networking.monitors instead.
    # - expectedOnline (optional, default true) Whether this host is expected
    #   to be reachable.  Hosts marked false are excluded from Prometheus
    #   scraping entirely, suppressing node_down and similar alerts.  Use for
    #   hosts that are legitimately powered off or decommissioned but not yet
    #   removed from facts.
    # - roaming (optional, default false) Whether or not this host roams on and
    #   off this network.  This is generally intended for personal laptops that
    #   will frequently be offline, and thus should not trigger alerts when
    #   offline.
    # - system The architecture-platform "double" suitable for the hostPlatform
    #   setting.
    # See https://stackoverflow.com/a/70106730 for how to setup Prometheus for
    # monitoring remote / uncontrolled systems (remote_read vs. remote_write).
    # There's a lot of silly work I do to fix this stuff.  I should write some
    # validators for this.
    hosts = {
      # This system is having boot issues.  Just take it out while I consider
      # next steps.
      # argon = {
      #   controlledHost = true;
      #   flake-input-overrides = {
      #     nixpkgs = "nixpkgs-nixos-raspberrypi";
      #   };
      #   ipv4 = 2;
      #   monitors = [
      #     "node"
      #     "systemd"
      #   ];
      #   networkInterface = "enu1u1";
      #   system = "aarch64-linux";
      # };
      arsenic = {
        blockProfiles = [ "kid-gaming-rig" ];
        controlledHost = true;
        ipv4 = 7;
        system = "x86_64-linux";
      };
      bromine = {
        controlledHost = true;
        flake-input-overrides = {
          nixpkgs = "nixpkgs-nixos-raspberrypi";
        };
        ipv4 = 3;
        system = "aarch64-linux";
      };
      cassandra-macbook = {
        blockProfiles = [ "adult" ];
        controlledHost = false;
        macAddresses = [
          "92:8b:79:8a:9e:c4"
          "bc:d0:74:23:21:1f"
        ];
        ipv4 = 224;
      };
      cassandra-iphone = {
        blockProfiles = [ "adult" ];
        controlledHost = false;
        macAddresses = [
          "a4:d2:3e:8f:46:0a"
        ];
      };
      cobalt = {
        controlledHost = true;
        flake-input-overrides = {
          nixpkgs = "nixpkgs-nixos-raspberrypi";
        };
        ipv4 = 11;
        system = "aarch64-linux";
      };
      copper = {
        controlledHost = true;
        expectedOnline = false;
        ipv4 = 10;
        system = "x86_64-linux";
      };
      gallium = {
        controlledHost = true;
        flake-input-overrides = {
          nixpkgs = "nixpkgs-nixos-raspberrypi";
        };
        ipv4 = 4;
        system = "aarch64-linux";
      };
      # germanium = {
      #   controlledHost = true;
      #   monitors = [
      #     "node"
      #     "systemd"
      #   ];
      #   system = "x86_64-linux";
      # };
      gateway = {
        controlledHost = false;
        ipv4 = 254;
        # The consumer router's LAN-side MAC.  vpn-reconcile uses the MAC(s) of
        # whichever host network.gateway-host points at to recognize the home
        # network at L2 (independent of the tunnel's state).  When silicon
        # becomes the router, flip network.gateway-host to "silicon" and this
        # entry's MAC becomes irrelevant.
        macAddresses = [
          "c8:63:fc:63:53:20"
        ];
        monitors = [ ];
      };
      lithium = {
        blockProfiles = [ "kid-gaming-rig" ];
        controlledHost = true;
        ipv4 = 8;
        # Only one of these MACs may hold the reservation at a time.  dnsmasq
        # accepts several MACs on a single dhcp-host entry, but it abandons the
        # lease held by one address when another asks for it — its own
        # documentation warns the arrangement is reliable only when exactly one
        # of the addresses is active.  With both NICs up the two interfaces
        # fought over 192.168.254.8, which presented as sporadic unreachability
        # (>90% loss on Prometheus scrapes) rather than an outright outage.
        # Ethernet is the intended path here, so the WiFi MAC stays parked
        # until we have a model for hosts that may appear on either link.
        macAddresses = [
          # "50:46:5d:a5:6d:e6" # WiFi.
          "f4:6d:04:21:dc:89" # Ethernet.
        ];
        system = "x86_64-linux";
      };
      lovelle-android = {
        blockProfiles = [ "adult" ];
        controlledHost = false;
        macAddresses = [
          "f0:d0:8c:0f:0c:5f"
        ];
        ipv4 = 149;
      };
      # HMH/NWEA work workstation.  The host entry stays here so the rest of
      # the network can resolve and reach it, but the host module is split:
      # the generic stub is at ../hosts/M-CL64PK702X.nix and the HMH-specific
      # extension lives in nix-config-hmh-private
      # (gitea.proton:logan/nix-config-hmh-private:hosts/M-CL64PK702X.nix),
      # which extends this configuration via `extendModules`.
      "M-CL64PK702X" = {
        controlledHost = true;
        blockProfiles = [ "adult" ];
        # flake-input-overrides = {
        #   nixpkgs = "nixpkgs-latest";
        # };
        ipv4 = 103;
        macAddresses = [
          "bc:d0:74:07:50:eb" # WiFi
          "c8:a3:62:84:33:99" # Ethernet dongle
        ];
        system = "aarch64-darwin";
      };
      manganese = {
        blockProfiles = [ "adult" ];
        controlledHost = false;
        ipv4 = 102;
        macAddresses = [
          "54:32:C7:B3:45:FC"
        ];
        system = "aarch64-ios";
      };
      nickel = {
        controlledHost = true;
        flake-input-overrides = {
          nixpkgs = "nixpkgs-nixos-raspberrypi";
        };
        ipv4 = 1;
        system = "aarch64-linux";
      };
      nucleus = {
        controlledHost = false;
        monitors = [ ];
        system = "x86_64-linux";
      };
      # No hostname here.  Bogus.
      patrick-lappy = {
        blockProfiles = [ "adult" ];
        controlledHost = false;
        ipv4 = 188;
        macAddresses = [ "14:ac:60:46:7d:af" ];
      };
      # rpi-installer = {
      #   controlledHost = false;
      #   flake-input-overrides = {
      #     nixpkgs = "nixpkgs-nixos-raspberrypi";
      #   };
      #   ipv4 = 253;
      #   monitors = [];
      #   system = "aarch64-linux";
      # };
      # A WiFi endpoint / extender / repeater, depending on how it is
      # configured.  I have it in the endpoint/extender mode, but its
      # configuration can go astray if it doesn't wake up in a positive state.
      # This is the default hostname.  I'm not sure how to configure it, and I
      # have two of them.  I'm unsure how to address them further.  But this
      # device is configured to have a static IP which is the same that I have
      # here.
      re500x = {
        controlledHost = false;
        # Not necessarily the most compact.  I was troubleshooting and needed to
        # pick something I was fairly certain was available.  Find lower IPs if
        # you're adding a new host.
        ipv4 = 20;
        monitors = [ ];
      };
      rubidium = {
        controlledHost = true;
        ipv4 = 13;
        system = "x86_64-linux";
      };
      scandium = {
        blockProfiles = [ "adult" ];
        controlledHost = true;
        flake-input-overrides = {
          nixpkgs = "nixpkgs";
        };
        ipv4 = 101;
        roaming = true;
        system = "aarch64-darwin";
      };
      selenium = {
        controlledHost = true;
        flake-input-overrides = {
          nixpkgs = "nixpkgs-nixos-raspberrypi";
        };
        ipv4 = 5;
        system = "aarch64-linux";
      };
      silicon = {
        # We might need to really specify this, because otherwise silicon winds
        # up blocking itself.
        blockProfiles = [ "adult" ];
        controlledHost = true;
        # Secondary addresses: additional IPs bound to the same interface.
        # Each entry generates a DNS A record; no DHCP reservation is created.
        extraAddresses = {
          silicon-external = 100;
        };
        flake-input-overrides = { };
        ipv4 = 9;
        macAddresses = [ "b8:ca:3a:77:a9:2a" ];
        networkInterface = "eth0";
        system = "x86_64-linux";
      };
      krypton = {
        controlledHost = true;
        ipv4 = 12;
        system = "x86_64-linux";
      };
      titanium = {
        blockProfiles = [ "adult" ];
        controlledHost = true;
        ipv4 = 6;
        system = "x86_64-linux";
      };

    }
    # This is sort of miscellaneous hosts that aren't part of critical
    # infrastructure.  I want them tracked so I know what kind of block
    # profiles they are, and I have a handy lookup should I need to identify
    # them later.
    # "uih" is short for unidentified host.
    // {
      uih0 = {
        mac = "ac:19:8e:f6:04:a0";
        ipv4 = 120;
      };
      some-unidentified-iphone = {
        mac = "ea:c6:99:b2:df:de";
        ipv4 = 121;
      };
      uih1 = {
        mac = "f0:a2:25:49:25:c8";
        ipv4 = 122;
      };
      uih2 = {
        mac = "32:ca:84:c2:82:7b";
        ipv4 = 123;
      };
      uih3 = {
        mac = "66:f2:6e:b8:a5:16";
        ipv4 = 124;
      };
      uih4 = {
        mac = "10:2c:b1:a5:ad:68";
        ipv4 = 125;
      };
      uih5 = {
        mac = "10:2c:b1:76:68:5d";
        ipv4 = 126;
      };
      uih6 = {
        mac = "ac:19:8e:1a:81:19";
        ipv4 = 127;
      };
      uih7 = {
        mac = "92:0a:15:a6:00:07";
        ipv4 = 128;
      };
      uih9 = {
        mac = "5e:8c:33:66:1d:65";
        ipv4 = 130;
      };
      uih10 = {
        mac = "76:3c:6c:a6:57:3c";
        ipv4 = 131;
      };
      uih11 = {
        mac = "28:cf:51:c9:1d:01";
        ipv4 = 132;
      };
      uih13 = {
        mac = "80:f3:ef:3b:b6:4d";
        ipv4 = 134;
      };
      uih14 = {
        mac = "10:2c:b1:8e:0f:ee";
        ipv4 = 135;
      };
      uih15 = {
        mac = "06:8a:dc:63:fe:e6";
        ipv4 = 136;
      };
      Tonal-080300100010266 = {
        mac = "10:59:17:00:cf:4f";
        ipv4 = 137;
      };
      Canonc618b2 = {
        mac = "20:0b:74:9a:21:2b";
        ipv4 = 138;
      };
      SOUNDPLUS_X_E0A8 = {
        mac = "02:22:6c:07:e0:a8";
        ipv4 = 139;
      };
      tasmota-8CFDB2-7602 = {
        mac = "d8:bc:38:8c:fd:b2";
        ipv4 = 140;
      };
      wyze-cam-of-some-kind = {
        mac = "2c:aa:8e:99:58:47";
        ipv4 = 175;
      };
      nintendo-switch-a = {
        mac = "28:cf:51:c9:1d:01";
        ipv4 = 242;
      };
      lwip0 = {
        mac = "20:f1:b2:26:b0:60";
        ipv4 = 185;
      };
      # What is this?
      ESP_45248A = {
        mac = "cc:7b:5c:45:24:8a";
        ipv4 = 141;
      };
      # What is this?
      S380HB = {
        mac = "90:bf:d9:3e:20:d8";
        ipv4 = 142;
      };
      WYZEC1-JZ-2CAA8E995847 = {
        mac = "2c:aa:8e:99:58:47";
        ipv4 = 143;
      };
      some-unidentified-apple-watch = {
        mac = "ee:b0:c4:e8:3e:c6";
        ipv4 = 144;
      };
      some-unidentified-mac-book-pro = {
        mac = "3e:8f:45:9d:b3:cd";
        ipv4 = 145;
      };
      iRobot-E49F9CCC561A410AB51B88723BB7BB1E = {
        mac = "50:14:79:b7:a1:b5";
        ipv4 = 146;
      };
      amazon-1fa3b1b81 = {
        mac = "40:b4:cd:35:85:61";
        ipv4 = 147;
      };
      roku3-667 = {
        controlledHost = false;
        # TODO: Find a better IP.
        ipv4 = 148;
        mac = "b0:a7:37:96:c6:33";
        blockProfiles = [ "streaming-device" ];
      };
    };

    ##
    # A user has the following structure:
    # ${username} = {
    #  description = "Description of user.";
    #  email = "email@domain";
    #  type = "person";
    #  full-name = "First Last";
    #  devices = [
    #    { host-id = "hostname"; ip = "20"; vpn = true; }
    #  ];
    # };
    users =
      # Interactive / human users.
      {
        cassandra = {
          description = "";
          type = "person";
          full-name = "Cassandra Barnett";
          ldap-groups = [
            "home-assistant-users"
            "openhab-users"
          ];
          devices = [
            {
              host-id = "cassandra-macbook";
              ip = "21";
              vpn = true;
            }
            {
              host-id = "cassandra-iphone";
              ip = "22";
              vpn = true;
            }
          ];
          blockProfiles = [
            "adult"
          ];
        };
        kai = {
          description = "";
          type = "person";
          full-name = "Kai Barnett";
          ldap-groups = [
            "screen-addicts"
          ];
          devices = [
            {
              host-id = "arsenic";
              vpn = false;
            }
          ];
          blockProfiles = [
            "child"
          ];
        };
        logan = {
          description = "The reason we suffer.";
          type = "person";
          full-name = "Logan Barnett";
          ldap-groups = [
            "3d-printer-admins"
            "3d-printer-printers"
            "gitea-admins"
            "gitea-users"
            "grafana-admins"
            "grafana-viewers"
            "home-assistant-admins"
            "home-assistant-users"
            "immich-admins"
            "immich-users"
            "mastodon-logustus-users"
            "mastodon-meshward-users"
            "mastodon-proton-users"
            "matrix-admins"
            "matrix-users"
            "nextcloud-admins"
            "nextcloud-users"
            "openhab-users"
            "wiki-admins"
            "wiki-users"
          ];
          devices = [
            {
              host-id = "scandium";
              ip = "20";
              vpn = true;
            }
            {
              host-id = "manganese";
              ip = "22";
              vpn = true;
            }
          ];
          blockProfiles = [
            "adult"
          ];
        };
        selena = {
          description = "";
          type = "person";
          full-name = "Selena";
          ldap-groups = [ ];
          devices = [
            {
              host-id = "selena-laptop";
              ip = "23";
              vpn = true;
            }
          ];
          blockProfiles = [
            "adult"
          ];
        };
        solomon = {
          description = "";
          type = "person";
          full-name = "Solomon Barnett";
          ldap-groups = [
            "screen-addicts"
          ];
          devices = [
            {
              host-id = "lithium";
              vpn = false;
            }
          ];
          blockProfiles = [
            "child"
          ];
        };
      }
      // {
        immich = {
          type = "oidc-client";
          description = "Immich OIDC client.";
          full-name = "immich";
          devices = [ ];
        };
        ivatar = {
          type = "oidc-client";
          description = "ivatar OIDC client.";
          full-name = "ivatar";
          devices = [ ];
        };
        openhab = {
          type = "oidc-client";
          description = "OpenHab OIDC client.";
          full-name = "openhab";
          devices = [ ];
        };
        mastodon-logustus = {
          type = "oidc-client";
          description = "Mastodon (logustus.com) OIDC client.";
          full-name = "mastodon-logustus";
          devices = [ ];
        };
        mastodon-meshward = {
          type = "oidc-client";
          description = "Mastodon (meshward.com) OIDC client.";
          full-name = "mastodon-meshward";
          devices = [ ];
        };
        mastodon-proton = {
          type = "oidc-client";
          description = "Mastodon (proton) OIDC client.";
          full-name = "mastodon-proton";
          devices = [ ];
        };
        wiki = {
          type = "oidc-client";
          description = "Org-wiki OIDC client.";
          full-name = "wiki";
          devices = [ ];
        };
        sftpgo = {
          type = "oidc-client";
          description = "SFTPGo OIDC client.";
          full-name = "sftpgo";
          devices = [ ];
        };
      };

    services = {

      immich = {
        authentication = "oidc";
        fqdn = "immich.${domain}";
        groups = [
          "immich-admins"
          "immich-users"
        ];
        redirectUris = [
          "https://immich.${domain}/auth/login"
          "https://immich.${domain}/user-settings"
          "app.immich:///oauth-callback"
        ];
      };

      openhab = {
        authentication = "oidc";
        fqdn = "openhab.${domain}";
        groups = [
          "openhab-admins"
          "openhab-users"
        ];
        # redirectUris = [
        #   "https://openhab.proton/outpost.goauthentik.io/callback"
        # ];
      };

      wiki = {
        authentication = "oidc";
        fqdn = "wiki.${domain}";
        # NixOS service name differs from the facts key.
        nixosService = "org-wiki-web";
        groups = [
          "wiki-admins"
          "wiki-users"
        ];
      };

      ivatar = {
        authentication = "oidc";
        fqdn = "ivatar.${domain}";
        # NixOS service name differs from the facts key.
        nixosService = "ivatar-host";
        groups = [ "ivatar-users" ];
        redirectUris = [
          "https://ivatar.${domain}/social/complete/oidc/"
        ];
      };

      mastodon-logustus = {
        authentication = "oidc";
        fqdn = "mastodon.logustus.com";
        groups = [ "mastodon-logustus-users" ];
        redirectUris = [
          "https://mastodon.logustus.com/auth/auth/openid_connect/callback"
        ];
        tokenEndpointAuthMethod = "client_secret_basic";
      };

      mastodon-meshward = {
        authentication = "oidc";
        fqdn = "mastodon.meshward.com";
        groups = [ "mastodon-meshward-users" ];
        redirectUris = [
          "https://mastodon.meshward.com/auth/auth/openid_connect/callback"
        ];
        tokenEndpointAuthMethod = "client_secret_basic";
      };

      mastodon-proton = {
        authentication = "oidc";
        fqdn = "mastodon.${domain}";
        groups = [ "mastodon-proton-users" ];
        redirectUris = [
          "https://mastodon.${domain}/auth/auth/openid_connect/callback"
        ];
        tokenEndpointAuthMethod = "client_secret_basic";
      };

      nextcloud = {
        authentication = "ldap";
        fqdn = "nextcloud.${domain}";
        groups = [
          "nextcloud-admins"
          "nextcloud-users"
        ];
        healthCheck = {
          subUri = "/status.php";
          conditions = [
            "[STATUS] == 200"
            "[BODY].installed == true"
            "[BODY].maintenance == false"
            "[RESPONSE_TIME] < 300"
            # Must have >7 days left.
            "[CERTIFICATE_EXPIRATION] > 168h"
          ];
        };
      };

      sftpgo = {
        authentication = "oidc";
        fqdn = "sftpgo.${domain}";
        groups = [
          "sftpgo-admins"
          "sftpgo-users"
        ];
        redirectUris = [
          "https://sftpgo.${domain}/web/oidc/redirect"
          "https://sftpgo.${domain}/web/oauth2/redirect"
        ];
        tokenEndpointAuthMethod = "client_secret_basic";
      };

      silicon-sonify = {
        authentication = "oidc";
        fqdn = "silicon-sonify.${domain}";
        nixosService = "sonify-health";
        groups = [ ];
      };

      titanium-sonify = {
        authentication = "oidc";
        fqdn = "titanium-sonify.${domain}";
        nixosService = "sonify-health";
        groups = [ ];
      };

    };

    # Mail-related facts.  Consumed by nixos-configs/stalwart-facts.nix to
    # generate the Stalwart configuration.  The internal domain
    # (network.domain) is implicit and not listed under externalDomains.
    mail = {
      externalDomains = {
        "meshward.com" = {
          dkimSelector = "default";
          dkimSecretName = "stalwart-dkim-meshward";
          # Optional facts.network.users attribute key.  When set, mail to
          # any unmatched address at this domain rewrites to that user's
          # derived primary address before LDAP verify runs.  null = strict
          # recipient matching.
          catchAllUser = null;
        };
        "logustus.com" = {
          dkimSelector = "default";
          dkimSecretName = "stalwart-dkim-logustus";
          catchAllUser = "logan";
        };
      };
    };

    monitoring = {
      # Dashboard definitions shared between the Grafana server and the kiosk
      # restart trigger.  Centralizing here lets both silicon (which hosts
      # Grafana) and bromine (which hosts the kiosk) compute the same hash
      # independently, so a dashboard change causes both to restart on deploy
      # without either host needing to reference the other.
      #
      # Callers invoke this as a function because the wireguard dashboard
      # requires lib and facts at call time.
      #
      # In all honesty, the panel definitions were vibe-coded.  There is
      # probably a mix of Grafana schema versions in here that is worth
      # cleaning up at some point.
      grafanaDashboards =
        { lib, facts }:
        let
          height = 9;
          # One third of a row.
          width = 8;
          without-socket-port =
            query:
            ''label_replace(${query}, "instance", "$1", "instance", "^(.*):[0-9]+$")'';
        in
        {
          active-alerts = import ../nixos-configs/grafana-active-alerts.nix { };
          dhcp = import ../nixos-configs/grafana-dhcp-monitor.nix {
            inherit height width without-socket-port;
          };
          dns-smart-block = import ../nixos-configs/grafana-monitor-dns.nix {
            inherit height width without-socket-port;
          };
          system-monitoring = import ../nixos-configs/grafana-host-monitor.nix {
            inherit height width without-socket-port;
          };
          garage-queue = import ../nixos-configs/grafana-garage-queue.nix {
            inherit without-socket-port;
          };
          nvidia-gpu = import ../nixos-configs/grafana-nvidia-gpu.nix {
            inherit without-socket-port;
          };
          power = import ../nixos-configs/grafana-power.nix { };
          uptime-timeseries = import ../nixos-configs/grafana-uptime-timeseries.nix {
            inherit without-socket-port;
          };
          uptime-stat = import ../nixos-configs/grafana-uptime-stat.nix {
            inherit without-socket-port;
          };
          wireguard = import ../nixos-configs/grafana-wireguard.nix {
            inherit lib facts;
          };
        };
    };

  };
}
