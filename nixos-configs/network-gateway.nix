################################################################################
# Toggleable network gateway module.
#
# When imported on a host, that host becomes the network's router/gateway.
# Combines VLAN sub-interfaces, NAT, inter-VLAN firewall, and per-VLAN DHCP
# into a single file that replaces the old silicon-vlans.nix, silicon-nat.nix,
# and silicon-vlan-firewall.nix.
#
# The VLAN plan itself (ids, subnets, roles) lives in facts.network.vlans —
# this module derives its interfaces, addressing, firewall, and DHCP from
# that, so adding a VLAN to facts is enough to route and serve it here.  The
# legacy VLAN carries the old mixed-trust 192.168.254.0/24 network unchanged;
# devices leave it through the admission flow, and it retires when empty.
#
# To activate:  Import this file in the host's config (e.g. silicon.nix).
# To deactivate: Remove/comment the import.  Everything reverts to the
#                consumer-router-as-gateway topology.
################################################################################
{
  config,
  facts,
  host-id,
  lib,
  ...
}:
let
  networkInterface = facts.network.hosts.${host-id}.networkInterface;
  vlans = facts.network.vlans;
  # Every VLAN this host routes and addresses by the ".1 is the gateway"
  # convention — everything except legacy, which keeps this host's
  # historical addressing until the subnet drains and dies.
  routedVlans = lib.subtractLists [ "legacy" ] (lib.attrNames vlans);
  gatewayAddress = name: "${vlans.${name}.prefix}.1";
  legacyAddress = "${vlans.legacy.prefix}.${
    toString facts.network.hosts.${host-id}.ipv4
  }";
in
{
  # 1. Declare this host as the gateway via DNS alias.
  networking.dnsAliases = [ "gateway" ];

  # 2. VLAN sub-interfaces on the physical trunk — one per facts VLAN, plus
  #    the wan uplink (VLAN 100, no internal subnet, addressed by ISP DHCP).
  networking.vlans =
    lib.mapAttrs (_: vlan: {
      id = vlan.id;
      interface = networkInterface;
    }) vlans
    // {
      wan = {
        id = 100;
        interface = networkInterface;
      };
    };

  # 3. IP addressing — the physical NIC has no IP, VLANs do.
  networking.interfaces = lib.mkMerge [
    (lib.genAttrs routedVlans (name: {
      ipv4.addresses = [
        {
          address = gatewayAddress name;
          prefixLength = vlans.${name}.prefixLength;
        }
      ];
    }))
    {
      # Legacy keeps this host's historical address and extra /32 service
      # addresses so nothing on the old network notices the cutover.
      legacy.ipv4.addresses = [
        {
          address = legacyAddress;
          prefixLength = vlans.legacy.prefixLength;
        }
      ]
      ++ (lib.mapAttrsToList (_: ipv4: {
        address = "${vlans.legacy.prefix}.${toString ipv4}";
        prefixLength = 32;
      }) (facts.network.hosts.${host-id}.extraAddresses or { }));
      wan.useDHCP = true;
      ${networkInterface}.ipv4.addresses = lib.mkForce [ ];
    }
    # Remove multi-interface static IP config (VLANs replace it).
    # dhcp-server.nix sets IPs on enp3s0/eno1/eth0/etc — not needed when
    # the gateway module puts IPs on VLAN interfaces instead.
    (lib.genAttrs [ "enp3s0" "eno1" "end0" "ens0" "eth0" ] (_: {
      ipv4.addresses = lib.mkForce [ ];
    }))
  ];

  # 4. This host IS the gateway — default route from WAN DHCP.
  #    Remove static defaultGateway that points at the old consumer router.
  networking.defaultGateway = lib.mkForce null;

  # 5. NAT: masquerade the internet-worthy VLANs + WireGuard out through
  #    wan.  Lobby and mgmt are deliberately absent — the lobby exists only
  #    to reach this host's enrollment services, and network gear has no
  #    business on the internet.
  #    externalInterface overrides wireguard's mkDefault, so iptables
  #    in wireguard/server-standard.nix automatically use "wan".
  boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;
  networking.nat.externalInterface = "wan";
  networking.nat.internalInterfaces = [
    "legacy"
    "main"
    "iot"
    "guest"
  ];

  # 6. VLAN isolation firewall.
  networking.nftables.enable = true;
  networking.nftables.tables.vlan-isolation = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        # Trusted reaches everything.  Legacy keeps its historical full
        # access while the admission flow drains it — tightening a
        # still-mixed network breaks the devices not yet migrated.
        iifname { "main", "legacy" } accept
        iifname "guest" oifname "wan" accept
        # Lobby and mgmt never forward: both exist only to talk to this
        # host, which is the input chain's business, not forwarding.
        # IoT: blocked by default. Per-device allowlist:
        #   iifname "iot" ip saddr 10.20.0.X oifname "wan" accept
      }
    '';
  };

  # 7. Override DHCP to serve per-VLAN ranges.  Each range sets a tag named
  #    for its VLAN, which scopes the per-VLAN router/DNS options below.
  services.dnsmasq.settings = {
    interface = lib.mkForce ([ "legacy" ] ++ routedVlans);
    bind-interfaces = true;
    dhcp-range = lib.mkForce [
      "set:legacy,${vlans.legacy.prefix}.175,${vlans.legacy.prefix}.250,12h"
      "set:main,${vlans.main.prefix}.100,${vlans.main.prefix}.250,12h"
      "set:iot,${vlans.iot.prefix}.100,${vlans.iot.prefix}.250,12h"
      "set:guest,${vlans.guest.prefix}.100,${vlans.guest.prefix}.250,1h"
      # Lobby leases are short-lived: devices either enroll and move on, or
      # leave.
      "set:lobby,${vlans.lobby.prefix}.100,${vlans.lobby.prefix}.250,10m"
      "set:mgmt,${vlans.mgmt.prefix}.100,${vlans.mgmt.prefix}.250,12h"
    ];
    dhcp-option = lib.mkForce (
      [
        "option:domain-search,${facts.network.domain}"
        "tag:legacy,option:router,${legacyAddress}"
        "tag:legacy,option:dns-server,${legacyAddress}"
      ]
      ++ lib.concatMap (name: [
        "tag:${name},option:router,${gatewayAddress name}"
        "tag:${name},option:dns-server,${gatewayAddress name}"
      ]) routedVlans
    );
  };
}
