################################################################################
# Maybe you've heard of Pi-Hole and that's cool and all but I wanted something
# declarative for blocking domains, and that's Blocky.  This is for blocking
# domains such as ad servers, malware, and so on.  I also get fine grained
# control to block specific hosts or groups of hosts from looking up groups of
# domains.  This makes it really easy to manage standard things I want blocked
# (like ads and malware) and some people get blocked more (like kids from adult
# sites, gaming, social media, etc).

# This reads heavily from ../nixos-modules/facts.nix.
#
# Blocky needs to stand in front of the entire DNS setup in order to work
# properly, since Blocky sees the DNS request coming from a client, and decides
# how to respond based on that client's definition in Blocky.  If Blocky were
# later in the DNS chain (like dnsmasq came first), then Blocky would only see
# dnsmasq talking to it, and we'd lose Blocky's power to block what we wanted by
# specific hosts or groups of hosts.
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
  inherit (lib) optionals optionalAttrs pipe;
  inherit (lib.attrsets) mapAttrs' mapAttrsToList;
  inherit (lib.lists)
    any
    flatten
    filter
    unique
    ;
  # DNS resolution flows: silicon (and other LAN clients) --> blocky:53 -->
  # unbound:5354 (loopback) --> root/TLD/authoritative servers.  Public
  # resolvers (OpenDNS et al.) are intentionally NOT in this chain -- the
  # whole point of standing up unbound was to get DNSBL lookups (Spamhaus)
  # working for stalwart, which the shared public resolvers block.  See
  # nixos-configs/unbound.nix.
  # TODO: Make this a dynamic value on the host.
  subnet = facts.network.subnets.barnett-main;

  host-ip = hostname: host: "${subnet}.${toString host.ipv4}";
  my-ip = host-ip host-id facts.network.hosts.${host-id};
  # This is because the names vary.  Instead of trying to guess, just set them
  # all.
  forced-ip-interface-config = {
    ipv4.addresses = [
      {
        address = my-ip;
        prefixLength = 24;
      }
    ];
  };
in
{
  networking.dnsAliases = [ "blocky" ];
  # TODO: Make dynamic some day.  Make it follow "gateway".
  networking.defaultGateway = "${subnet}.254";
  # Allow actual DNS and DHCP connections.
  networking.firewall.allowedUDPPorts = [ 53 ];
  # Larger connections (DNSSEC, zone transfers) use TCP for DNS.
  networking.firewall.allowedTCPPorts = [ 53 ];
  # Silicon's own resolver goes through the local stack so its mail server
  # (stalwart) hits unbound for SURBL lookups instead of public resolvers.
  networking.nameservers = [ "127.0.0.1" ];
  services.https.fqdns."blocky.${facts.network.domain}" = {
    enable = true;
    internalPort = config.services.blocky.settings.ports.http;
  };
  services.blocky = {
    enable = true;
    settings = {
      ports = {
        dns = 53;
        http = 4000;
      };
      # Forward external DNS queries to our local recursive resolver -- needed
      # so DNSBL lookups (Spamhaus) reach the auth servers from our own
      # resolver IP instead of a shared public one.  See
      # nixos-configs/unbound.nix.
      upstream.default = [ "127.0.0.1:5354" ];
      # Conditional forwarding: Forward .proton domain queries to dnsmasq for
      # local hostname resolution. Dnsmasq runs on port 5353 to avoid conflict
      # with blocky on port 53.
      conditional.mapping."proton" = "127.0.0.1:5353";
      # Look up client hostnames (reverse DNS for identifying who is making
      # requests) from dnsmasq.
      clientLookup = {
        upstream = "127.0.0.1:5353";
        singleNameOrder = [ 1 ];
        # You actually want `blocking.denylists` instead of `clients`.
        # clients = [];
      };
      blocking = {
        # Blocky's download timeout defaults to 5s, and it is not a network
        # timeout -- it bounds the whole request including reading the body,
        # and blocky validates every domain as it streams.  Parsing is the
        # actual cost: on silicon the updater serves ads.txt (23 MB) over
        # loopback in ~16 ms, but blocky only gets through ~300k of its ~1M
        # entries before 5s expires, so the import truncates with "non
        # resumable parse error: context deadline exceeded".  ads, adult, and
        # malware were all silently loading partial lists.  60s leaves ample
        # headroom at the observed ~60k entries/sec, even with four sources
        # parsing concurrently.
        #
        # `strategy = "fast"` is what makes that generous timeout safe.  The
        # default ("blocking") holds the DNS listener down until every source
        # finishes, so timeout multiplies into startup latency: 23 sources at
        # concurrency 4 and 3 attempts is 6*3*60s ~= 18 minutes of no DNS for
        # the entire network if sources hang.  Since blocky is the only
        # resolver here, that is a far worse failure than briefly under-
        # blocking.  With "fast", lists load asynchronously and DNS is up
        # immediately.
        #
        # The tradeoff is a window after restart where blocking is not fully
        # active.  That window already exists regardless: blocky-lists-updater
        # is ordered *after* blocky, so every updater-served list fails its
        # first fetch with "connection refused" and only lands when the updater
        # comes up and calls /api/lists/refresh.
        loading = {
          strategy = "fast";
          downloads.timeout = "60s";
        };
        # No list sources are defined here, deliberately.  They live in
        # blocky-with-updater.nix (this file's only importer), which points
        # Blocky at locally-aggregated copies served by blocky-lists-updater;
        # the canonical upstream URLs are that module's `sources` attribute.
        # The `gaming` and `video-streaming` groups are injected by
        # dns-smart-block's `autoMapAllBlocklists` rather than declared in
        # either file -- it emits one group per *enabled classifier*, so
        # enabling a classifier there creates the group but does not enforce
        # it.  Enforcement only happens when a profile below names the group;
        # `video-streaming` sat downloaded-but-unconsulted for exactly that
        # reason.  Adding a classifier means editing `profileGroups` too.
        #
        # The upstream URLs used to be duplicated here as a `blackLists`
        # definition.  Because `services.blocky.settings` is freeform, the
        # module system merges same-named list options from multiple modules by
        # *concatenation* -- there is no "override" happening -- so Blocky
        # ended up fetching both the local aggregates and the same upstreams
        # again directly: 23 sources instead of 9, roughly doubling list
        # download and parse work on every startup and refresh.  If you add a
        # list group, add it to blocky-with-updater.nix, not here.
        # `allowlists` (the modern name for `whiteLists`) does work as of blocky
        # 0.27 -- in that version `blackLists`/`whiteLists` are accepted only as
        # deprecated aliases that get migrated to `denylists`/`allowlists`.  It
        # is configured over in blocky-with-updater.nix, which is what
        # dns-server.nix actually imports; see the comment there for the
        # rationale and for the deny-all footgun to avoid.
        clientGroupsBlock =
          let
            # Maps profile names to the blacklist groups they enforce.  The
            # "default" key is a Blocky special that applies to any client not
            # matched by a more specific entry.
            profileGroups = {
              adult = [
                "ads"
                "malware"
              ];
              child = [
                "ads"
                "adult"
                "gaming"
                "malware"
                "video-streaming"
              ];
              kid-gaming-rig = [
                "ads"
                "adult"
                "malware"
                "video-streaming"
              ];
              # TODO: Consider making a guest profile, wherein only a select
              # allow list is used.  All hosts either use this unless they are
              # declared somewhere via facts.  This can help some entities from
              # dialing home.
              default = [
                "ads"
                "adult"
                "gaming"
                "malware"
                "video-streaming"
              ];
            };
            # TODO: The current approach is flawed in that it assumes that the
            # only way to declare the presence of a host is via the hosts
            # declaration, but users can have devices which indicate IPs to use
            # for the VPN.  What we should probably do is move it such that the
            # host itself declares what sort of VPN IPs it can have and have the
            # rest of the machinery follow.  This should be more preferable than
            # having to check a user's device list.
            # blockProfilesForHost = otherHostId: pipe facts.network.users [
            #   (filter (u: any (d: d.host-id == otherHostId) u.devices))
            #   (map (u: u.blockProfiles or []))
            #   flatten
            #   unique
            # ];
            profilesByHosts = pipe facts.network.hosts [
              (mapAttrsToList (
                name: data:
                let
                  blockProfiles = data.blockProfiles or [ "default" ];
                  # Profile names must expand to blacklist group names before
                  # reaching Blocky; passing a profile name directly would match
                  # a same-named blacklist instead.  Unknown profile names throw
                  # rather than silently producing an empty (unfiltered) entry.
                  blockLists = pipe blockProfiles [
                    (map (
                      p:
                      if profileGroups ? ${p} then
                        profileGroups.${p}
                      else
                        throw "blocky: unknown block profile '${p}' on host '${name}'"
                    ))
                    flatten
                    unique
                  ];
                in
                [
                  {
                    name = "${name}.${facts.network.domain}";
                    value = blockLists;
                  }
                  {
                    inherit name;
                    value = blockLists;
                  }
                ]
                ++ (optionals (data.ipv4 or null != null) [
                  {
                    name = "${facts.network.subnets.barnett-main}.${toString data.ipv4}";
                    value = blockLists;
                  }
                ])
                ++ (map (mac: {
                  name = mac;
                  value = blockLists;
                }) (data.macAddresses or [ ]))
              ))
              flatten
              builtins.listToAttrs
            ];
          in
          { inherit (profileGroups) default; } // profilesByHosts;
      };
      prometheus.enable = true;
    };
  };
  # Hold blocky.service in `activating` until DNS actually answers.  blocky
  # has no sd_notify support and won't get it -- upstream's stance is that
  # platform-integration surface (incl. systemd) lives outside the project
  # (see PR #244, where the maintainer declined a systemd installation
  # guide).  So `Type=notify` is unavailable and `After=blocky.service`
  # only sequences against fork, not readiness -- which races dependents
  # like nextcloud-custom-config that resolve via blocky.  `blocky
  # healthcheck` is upstream's documented liveness probe (issue #1304); we
  # poll it from ExecStartPost so systemd holds activation until DNS is
  # serving.
  systemd.services.blocky.serviceConfig.ExecStartPost =
    pkgs.writeShellScript "blocky-wait-ready" ''
      for i in {1..60}; do
        ${pkgs.blocky}/bin/blocky healthcheck && exit 0
        sleep 1
      done
      exit 1
    '';
  # Announce blocky as this host's NSS DNS provider, so DNS-dependent units
  # can `After=nss-lookup.target` and stay agnostic to which resolver
  # (blocky/unbound/dnsmasq/etc.) is in play.  Reaches `active` only after
  # the ExecStartPost healthcheck above succeeds, so nss-lookup.target
  # inherits real-readiness gating, not just fork-vs-active.
  #
  # PropagatesStopTo couples the target to blocky's lifecycle: when blocky
  # stops (incl. as part of a restart during nixos-rebuild switch), the
  # target stops too, then is pulled back in via the `Wants=` edge during
  # blocky's restart.  This makes the target actually follow runtime
  # restarts, which `Before=`/`Wants=` alone do not -- those are
  # activation-graph directives, not lifecycle coupling.
  systemd.services.blocky = {
    wants = [ "nss-lookup.target" ];
    before = [ "nss-lookup.target" ];
    # `requiredBy` translates to `Requires=` from the target side: target
    # activation pulls the provider in, AND if the provider fails to come
    # up, the target also fails.  Failure-cascade is the right semantic
    # here -- "DNS isn't actually serving" should surface as a clear
    # `nss-lookup.target failed`, not as cryptic per-consumer resolve
    # errors after the target falsely reaches `active` with no providers.
    # (Upstream nixpkgs unbound uses `wantedBy` instead; consider promoting
    # there too in the upstream PR.)
    requiredBy = [ "nss-lookup.target" ];
    unitConfig.PropagatesStopTo = "nss-lookup.target";
  };
  # Goss health checks for Blocky DNS.
  services.goss.checks = {
    # Check that the HTTPS endpoint is responding.
    http."https://blocky.${facts.network.domain}/" = {
      status = 200;
      timeout = 5000;
    };
    # Check that the Blocky API endpoint works.
    http."https://blocky.${facts.network.domain}/api/blocking/status" = {
      status = 200;
      timeout = 3000;
    };
    # Verify DNS port is listening (UDP).  DNS is the core functionality of
    # Blocky.  Blocky binds to :: (IPv6 any) which also accepts IPv4
    # connections via IPv4-mapped IPv6 addresses.
    port."udp6:53" = {
      listening = true;
    };
    # Check that DNS port is listening (TCP).  Used for larger DNS responses
    # and zone transfers.
    port."tcp6:53" = {
      listening = true;
    };
    # Functional DNS test: Verify blocky can resolve external domains through
    # its ad-blocking pipeline and upstream DNS servers.
    dns."example.com" = {
      resolvable = true;
      server = "127.0.0.1";
      timeout = 3000;
    };
    # Check that the blocky service is running.
    service.blocky = {
      enabled = true;
      running = true;
    };
  };
}
