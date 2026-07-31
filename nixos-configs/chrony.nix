################################################################################
# Time synchronization for all Linux hosts, via chrony.
################################################################################
{ ... }:
{
  # chrony rather than the default systemd-timesyncd.  timesyncd is a plain
  # SNTP client: per its own documentation it contacts servers "in turn, until
  # one responds," then trusts whatever that one says — no cross-comparison
  # between sources, no outlier rejection.  That buys availability but not
  # correctness, and correctness is what matters here, because these hosts hold
  # TLS certs, validate DNSSEC, and authenticate RADIUS.  chrony polls all
  # sources concurrently, runs a selection algorithm, and discards falsetickers.
  #
  # Enabling chrony sets services.timesyncd.enable = false via mkForce, so
  # there is no conflict to manage.
  #
  # THE COLD-START DEADLOCK, and why literal IPs lead the list
  # ─────────────────────────────────────────────────────────
  # DNSSEC validation is time-dependent: RRSIG records carry inception and
  # expiration timestamps, so a badly wrong clock makes validation fail and the
  # resolver answers SERVFAIL.  If every NTP server is named rather than
  # addressed, that deadlocks — a bad clock breaks DNS, broken DNS prevents
  # resolving the NTP pool, and so the clock is never corrected.  silicon hit
  # exactly this, most likely after losing its CMOS battery.
  #
  # silicon is the acute case because it validates DNSSEC locally via unbound;
  # other hosts merely ask silicon, which validates using *its* clock.  But the
  # literal IPs belong on every host anyway: silicon is also the network's
  # resolver, so when silicon's clock is wrong nothing on the network can
  # resolve anything, and a by-name-only list would strand every host at once.
  # The IP anchors decouple each host's time bootstrap from silicon's health.
  #
  # Server selection favors national metrology institutes — the organizations
  # that define the second — since they publish stable addresses and have no
  # commercial interest in the query.
  #
  # NTS (services.chrony.enableNTS) is deliberately left off.  Network Time
  # Security establishes keys over TLS, which requires a valid clock, which is
  # precisely the thing we cannot assume during a cold start.
  #
  # ORDERING: unbound starts *before* chronyd, and has to stay that way
  # ──────────────────────────────────────────────────────────────────
  # The instinct is to order chronyd ahead of unbound so the resolver never
  # sees a bad clock.  That edge cannot exist.  nixpkgs already declares the
  # opposite, and for a good reason — chronyd wants DNS for the named servers
  # below:
  #
  #   unbound.service   Before=nss-lookup.target
  #   chronyd.service   After=nss-lookup.target
  #
  # nss-lookup.target is a passive target, but on silicon it is genuinely
  # active — gitea, authelia, rpc-statd and friends pull it in — so that
  # ordering takes effect rather than sitting inert.  Adding `chronyd before
  # unbound`, or the tidier-looking `unbound after time-sync.target`, closes a
  # cycle:
  #
  #   unbound → nss-lookup.target → chronyd → time-sync.target → unbound
  #
  # systemd resolves a cycle by deleting an edge of its own choosing and
  # logging "Found ordering cycle".  That trades a known boot order for an
  # arbitrary one, on the host that is the network's only resolver.  Strictly
  # worse than leaving it alone.
  #
  # Three things make the cold start work without that edge:
  #
  #   1. The literal IPs are load-bearing precisely here.  chronyd resolves
  #      initstepslew hostnames synchronously while parsing its config and, on
  #      failure, logs "Could not resolve address of initstepslew server" and
  #      drops them — no retry, no wait.  So when a bad clock has soured DNS,
  #      the three named entries are skipped and the literal IPs are the
  #      entire initstepslew source set.  A names-only list would leave it
  #      with no sources at all, and the step would never happen.
  #   2. chronyd is Type=notify and sends READY=1 only after the step
  #      completes, so time-sync.target genuinely means "clock corrected".
  #      unbound simply cannot be one of the units that benefits from it.
  #   3. unbound does not cache the failure for long.  Bogus DNSSEC results
  #      expire per val-bogus-ttl (60s by default), so validation starts
  #      succeeding on its own about a minute after chrony steps the clock —
  #      no restart, no intervention.
  services.chrony = {
    enable = true;
    servers = [
      # Literal IPs: the DNS-independent cold-start path.  These also feed the
      # initstepslew directive (enabled by default, 1000s threshold), which is
      # what actually rescues a wildly wrong clock at boot by stepping it
      # rather than slewing.
      "192.53.103.108" # ptbtime1.ptb.de — PTB, German national metrology
      "192.53.103.104" # ptbtime2.ptb.de
      "192.53.103.103" # ptbtime3.ptb.de
      "129.6.15.28" # time-a-g.nist.gov — NIST, USA
      "162.159.200.123" # time.cloudflare.com — anycast
      "162.159.200.1" # time.cloudflare.com — anycast
      # The same operators by name, hedging against renumbering of the
      # addresses above.  These are knowingly redundant: chrony treats a name
      # and its resolved address as two independent sources, so each entry
      # double-polls one machine and contributes two correlated votes to source
      # selection.  Harmless with this many sources, but a deliberate trade for
      # renumbering resilience rather than an oversight.
      "ptbtime1.ptb.de"
      "time-a-g.nist.gov"
      "time.cloudflare.com"
    ];
    # The public pool is deliberately absent from `servers` above, which emits
    # static `server` lines.  Pool membership churns by design — its DNS TTL is
    # roughly 5 minutes against roughly 4 hours for the institutional records —
    # so pool hostnames belong in the `pool` directive, which tracks that churn
    # and selects a live subset.  Never pre-resolve pool names into literal
    # IPs: that hammers a volunteer's server long after they have withdrawn
    # from the pool, which the project explicitly asks people not to do.
    extraConfig = ''
      pool 2.nixos.pool.ntp.org iburst maxsources 3
    '';
  };
}
