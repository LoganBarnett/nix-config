################################################################################
# Uses the "standard" networking seen in the NixOS wiki here:
# https://wiki.nixos.org/wiki/WireGuard
# I don't know what word better than "standard" would work.  The other is using
# networkd.  I tried getting networkd working, but I can't even get Wireguard to
# show me its configuration.
################################################################################
{
  config,
  facts,
  host-id,
  lib,
  pkgs,
  ...
}:
let
  wireguard-port = 51820;
  vpn-subnet-prefix = "192.168.102";
  network-interface = facts.network.hosts.${host-id}.networkInterface or "enp0";
  peers = lib.pipe facts.network.users [
    (lib.attrsets.mapAttrsToList (name: user: user.devices))
    lib.lists.flatten
    (lib.lists.filter (d: d.vpn))
    (lib.lists.map (d: {
      inherit (d) host-id ip;
    }))
  ];
  # Group the vpn devices by their assigned host octet so a duplicate is caught
  # at build time.  A collision is not something WireGuard reports: given two
  # peers with the same allowed-ip the server silently keeps the /32 on one and
  # leaves the other with none, blackholing the loser's return traffic.  The
  # assertion below turns that into a build failure instead.
  vpnIpToHosts = lib.foldl' (
    acc: p: acc // { ${p.ip} = (acc.${p.ip} or [ ]) ++ [ p.host-id ]; }
  ) { } peers;
  vpnIpCollisions = lib.filterAttrs (
    _: hosts: builtins.length hosts > 1
  ) vpnIpToHosts;
  wireguard-client-peer =
    { host-id, ip }:
    {
      # Name the peer unit after the device.  The module otherwise derives the
      # name from the (escaped) public key, which is unreadable and cannot be
      # referenced by the restartTriggers below.  Host-ids are unique per peer,
      # so the resulting wireguard-wg0-peer-<host-id>.service names are unique.
      name = host-id;
      # This demands the actual key and not a path.  Use the ./. idiom to get the
      # path but also put this file in the nix store where we can get to it.
      publicKey = builtins.readFile ../../secrets/${host-id}-wireguard-client.pub;
      allowedIPs = [ "${vpn-subnet-prefix}.${ip}/32" ];
    };
  wireguard-client-secret = host-id: {
    "${host-id}-wireguard-client" = {
      generator.script = "wireguard-priv";
      rekeyFile = ../../secrets/${host-id}-wireguard-client.age;
    };
  };
  clientPeers = builtins.map wireguard-client-peer peers;
  # A digest of the entire peer set, attached as a restartTrigger to every peer
  # unit below.  nixos-rebuild only restarts a peer unit whose own text changed.
  # The cost is a sub-second reconnect for every peer whenever the set changes,
  # which is rare.
  peerSetDigest = builtins.hashString "sha256" (builtins.toJSON clientPeers);
in
{
  assertions = [
    {
      assertion = vpnIpCollisions == { };
      message =
        "WireGuard client VPN addresses must be unique per device, but "
        + "facts.network.users assigns the same address to more than one "
        + "device.  The server drops the duplicate allowed-ip, silently "
        + "blackholing one peer's return traffic.  Collisions:\n"
        + lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            ip: hosts: "  ${vpn-subnet-prefix}.${ip} -> ${lib.concatStringsSep ", " hosts}"
          ) vpnIpCollisions
        );
    }
  ];
  age.secrets = {
    "${host-id}-wireguard-server" = {
      generator.script = "wireguard-priv";
      rekeyFile = ../../secrets/${host-id}-wireguard-server.age;
    };
  }
  // (lib.attrsets.mergeAttrsList (
    builtins.map wireguard-client-secret (builtins.map (p: p.host-id) peers)
  ));
  imports = [
    ../../agenix/wireguard-priv.nix
  ];
  environment.systemPackages = [
    # Allow us to run Wireguard commands to show configuration and diagnose
    # issues.
    pkgs.wireguard-tools
  ];
  networking.monitors = [ "wireguard" ];
  networking.nat.enable = true;
  networking.nat.externalInterface = lib.mkDefault network-interface;
  networking.nat.internalInterfaces = [ "wg0" ];
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
  };

  # This was suggested as some troubleshooting, but after moving hosts it didn't
  # seem to manifest.  I'd just leave this for reference for now.
  # networking.interfaces.wg0 = {
  #   # DHCP doesn't make sense here, since everything is statically defined.
  #   # Having this set to be true might be causing this issue from
  #   # `network-setup-start` as well:
  #   # Nexthop has invalid gateway.
  #   useDHCP = false;
  # };
  # Just belt-and-suspenders to making sure we don't use DHCP in our Wireguard
  # interface.  It's to hopefully prevent these kinds of issues arising in
  # `network-setup-start`:
  # Nexthop has invalid gateway.
  # networking.dhcpcd.denyInterfaces = [ "wg0" ];

  # Reload every peer unit whenever the peer set changes.  See peerSetDigest.
  systemd.services = builtins.listToAttrs (
    builtins.map (
      p:
      lib.nameValuePair "wireguard-wg0-peer-${p.host-id}" {
        restartTriggers = [ peerSetDigest ];
      }
    ) peers
  );

  networking.wireguard.enable = true;
  networking.wireguard.interfaces = {
    # "wg0" is the network interface name. You can name the interface
    # arbitrarily.
    wg0 = {
      # Determines the IP address and subnet of the server's end of the tunnel
      # interface.
      ips = [ "${vpn-subnet-prefix}.1/24" ];

      # The port that WireGuard listens to. Must be accessible by the client.
      listenPort = 51820;

      # This allows the wireguard server to route your traffic to the Internet
      # and hence be like a VPN For this to work you have to set the dnsserver
      # IP of your router (or dnsserver of choice) in your clients.
      postSetup = ''
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${vpn-subnet-prefix}.0/24 -o ${config.networking.nat.externalInterface} -j MASQUERADE
      '';

      # This undoes the above command.
      postShutdown = ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${vpn-subnet-prefix}.0/24 -o ${config.networking.nat.externalInterface} -j MASQUERADE
      '';

      privateKeyFile = config.age.secrets."${host-id}-wireguard-server".path;
      peers = clientPeers;
      # peers = [
      #   # List of allowed peers.
      #   { # Feel free to give a meaning full name
      #     # Public key of the peer (not a file path).
      #     publicKey = "{client public key}";
      #     # List of IPs assigned to this peer within the tunnel subnet. Used to configure routing.
      #     allowedIPs = [ "10.100.0.2/32" ];
      #   }
      #   { # John Doe
      #     publicKey = "{john doe's public key}";
      #     allowedIPs = [ "10.100.0.3/32" ];
      #   }
      # ];
    };
  };
}
