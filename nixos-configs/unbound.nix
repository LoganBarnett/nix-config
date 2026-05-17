################################################################################
# Unbound: validating recursive DNS resolver, loopback-only.
#
# Sits north of blocky in the DNS chain (closer to the public internet):
#
#   clients --> blocky:53 --> unbound:5354 --> root/TLD/authoritative servers
#                       \--> dnsmasq:5353 (for .proton local zone)
#
# Motivation: DNSBL spam-filter zones (Spamhaus dbl/zen, etc.) block queries
# from shared public resolvers because they cannot rate-limit per user.  The
# blocking is silent -- Cloudflare and Quad9 return the sentinel
# 127.255.255.254 instead of real listing codes, which a naive consumer treats
# as "listed" and rejects every probed address.  Running our own recursive
# resolver gives stalwart's spam-filter pipeline real Spamhaus data.  Privacy
# and local DNSSEC validation are bonuses; DNSBL is the load-bearing reason.
#
# This is pure recursion -- no forwarders.  Forwarding back to OpenDNS et al.
# would defeat the entire purpose, since their IPs are what get blocked (or
# in OpenDNS's case, only work because of a fragile paid arrangement).
#
# Acceptance check: `dig @silicon.proton dbltest.com.dbl.spamhaus.org` should
# return 127.0.1.2.  Anything returning 127.255.255.254 means the query
# escaped through a public resolver.
################################################################################
{ ... }:
{
  services.unbound = {
    enable = true;
    # Bring root DNSSEC trust anchor up to date via unbound-anchor.  Default
    # is true, set explicitly for documentation.
    enableRootTrustAnchor = true;
    # Expose unbound-control over a local UNIX socket for `unbound-control
    # stats_noreset` and friends.  No network exposure.
    localControlSocketPath = "/run/unbound/unbound.ctl";
    settings = {
      server = {
        # Loopback only -- the only client is blocky on the same host.
        interface = [ "127.0.0.1" ];
        port = 5354;
        # Only accept queries from localhost.
        access-control = [ "127.0.0.0/8 allow" ];

        # Privacy / hardening.
        hide-identity = true;
        hide-version = true;
        harden-glue = true;
        harden-dnssec-stripped = true;
        harden-below-nxdomain = true;
        qname-minimisation = true;

        # Cache sizing.  64M each is generous for a household but cheap on
        # silicon.  Prefetch refreshes popular records before TTL expiry so
        # cold-cache pain is hidden from the user.
        msg-cache-size = "64m";
        rrset-cache-size = "64m";
        cache-min-ttl = 300;
        cache-max-ttl = 86400;
        prefetch = true;
        prefetch-key = true;
        # Serve stale answers (briefly) while a refresh is in flight to keep
        # latency low when upstream is slow.
        serve-expired = true;
        serve-expired-ttl = 3600;
      };
    };
  };

  # Blocky's upstream now points at unbound; if unbound isn't up, blocky has
  # nothing to forward to.  Hard ordering + requires so blocky waits for
  # unbound to be ready before starting and restarts if unbound restarts.
  systemd.services.blocky = {
    after = [ "unbound.service" ];
    requires = [ "unbound.service" ];
  };

  # Health checks.  Unbound binds 127.0.0.1:5354 so the port check is udp/tcp
  # (IPv4), not udp6/tcp6 like blocky.
  services.goss.checks = {
    port."udp:5354" = {
      listening = true;
      ip = [ "127.0.0.1" ];
    };
    port."tcp:5354" = {
      listening = true;
      ip = [ "127.0.0.1" ];
    };
    service.unbound = {
      enabled = true;
      running = true;
    };
  };
}
