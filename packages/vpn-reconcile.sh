################################################################################
# vpn-reconcile — keep the WireGuard tunnel in the desired state as the laptop
# roams.
#
# This is a *level-triggered, idempotent* reconciler: it senses the current
# network and the tunnel's health, then drives toward the desired state.  It is
# safe to run on a timer and on network/power events alike — every invocation
# does the same "look at reality, fix what's wrong" pass, so a missed or
# duplicated event can never corrupt state (worst case: a fix waits for the next
# tick).  Concurrent runs are serialized with a directory lock.
#
# Desired state:
#   - On the home LAN          → tunnel DOWN (direct laptop↔silicon, no hairpin).
#   - Roaming, normal mode     → split tunnel (SPLIT_IFACE): only home subnets
#                                ride the tunnel; the internet stays direct, so a
#                                dead tunnel never interrupts normal routing.
#   - Roaming, travel mode     → full tunnel (FULL_IFACE): everything exits via
#                                home.  Fail-closed by construction — while the
#                                tunnel is down the default route blackholes
#                                rather than leaking onto an untrusted network.
#
# Home detection is done at L2/DHCP (gateway MAC + subnet), NOT by probing a
# home host — a home IP is reachable both directly at home and *through* the
# split tunnel when roaming, so it cannot distinguish the two.  The gateway MAC
# is read independently of the routing table, so it holds even when the full
# tunnel owns the default route.
#
# Runs as root (via sudo): wg-quick and route manipulation require it.
#
# Config variables are baked in by the Nix derivation and prepended above this
# file: HOME_GATEWAY_MACS, HOME_SUBNET_PREFIX, SPLIT_IFACE, FULL_IFACE,
# TUNNEL_PROBE_IP, STATE_DIR, HANDSHAKE_MAX_AGE.
################################################################################

# macOS system tools, referenced by absolute path.  These are deliberately the
# Apple system binaries rather than Nix-provided ones, for two reasons:
#   - No Nix equivalent exists: `ipconfig getoption` (read the DHCP lease) and
#     `scutil` (SystemConfiguration) are Apple-only tools.
#   - Behavioral mismatch with the Nix/Linux versions: macOS `ping -t` is a
#     total timeout, whereas iputils/GNU `ping -t` is TTL — a silent footgun
#     for the 1–3s probes below; `arp`/`ifconfig` emit BSD-format output (and
#     macOS `ifconfig -l`); `stat -f %m` is BSD (GNU stat uses `-c %Y`).
# DNS is not a factor: every probe below targets a literal IP, never a hostname,
# so no resolver is exercised.  (And on darwin even Nix binaries resolve through
# libSystem, so there is no Nix-vs-system resolver split to worry about.)  The
# tunnel tools — wg / wg-quick / wireguard-go — remain the Nix-built ones via
# the derivation's runtime inputs; those are exactly what we want.
readonly ARP=/usr/sbin/arp
readonly IFCONFIG=/sbin/ifconfig
readonly IPCONFIG=/usr/sbin/ipconfig
readonly PING=/sbin/ping
readonly SCUTIL=/usr/sbin/scutil
readonly STAT=/usr/bin/stat

log() {
  printf '[vpn-reconcile] %s\n' "$*"
}

# Pad each octet of a MAC to two lowercase hex digits so values from `arp`
# (which strips leading zeros, e.g. "8:0:27:...") compare equal to the fully
# written facts values ("b8:ca:3a:...").  Uses gawk's strtonum.
normalize_mac() {
  printf '%s' "$1" | awk -F: '{
    out = "";
    for (i = 1; i <= NF; i++) {
      out = out (i > 1 ? ":" : "") sprintf("%02x", strtonum("0x" $i));
    }
    print out;
  }'
}

# Echo "<iface> <gateway-ip>" for the active physical link, independent of the
# VPN tunnel's routes: it reads the DHCP lease (ipconfig getoption), not the
# routing table, so a full tunnel hijacking the default route does not hide the
# physical gateway.  Returns non-zero when no physical gateway is found.
physical_gateway() {
  local primary iface router
  local -a candidates rest
  primary="$(echo 'show State:/Network/Global/IPv4' | "$SCUTIL" \
    | awk -F': ' '/PrimaryInterface/ { print $2 }' | tr -d ' ' || true)"
  read -r -a rest <<< "$("$IFCONFIG" -l 2>/dev/null || true)"
  # Try the primary service first, then any other real interface.
  candidates=("$primary" "${rest[@]}")
  for iface in "${candidates[@]}"; do
    case "$iface" in
      lo*|utun*|gif*|stf*|awdl*|llw*|ppp*|ipsec*|"") continue ;;
    esac
    router="$("$IPCONFIG" getoption "$iface" router 2>/dev/null || true)"
    if [[ -n "$router" ]]; then
      printf '%s %s' "$iface" "$router"
      return 0
    fi
  done
  return 1
}

# True when physically on the home LAN: the default gateway's MAC matches a
# configured home-gateway MAC AND our address is in the home subnet.  Both are
# L2/DHCP facts, so this holds regardless of the tunnel's state.
at_home() {
  local iface gw our_ip gw_mac mac pg
  local -a macs
  pg="$(physical_gateway || true)"
  [[ -n "$pg" ]] || return 1
  iface="${pg%% *}"
  gw="${pg##* }"
  our_ip="$("$IPCONFIG" getifaddr "$iface" 2>/dev/null || true)"
  [[ "$our_ip" == "$HOME_SUBNET_PREFIX".* ]] || return 1
  # Prime the ARP cache, then read the gateway's MAC.
  "$PING" -c 1 -t 1 "$gw" >/dev/null 2>&1 || true
  gw_mac="$("$ARP" -n "$gw" 2>/dev/null | awk '{ print $4 }' | head -n1 || true)"
  [[ "$gw_mac" == *:* ]] || return 1
  gw_mac="$(normalize_mac "$gw_mac")"
  read -r -a macs <<< "${HOME_GATEWAY_MACS}"
  for mac in "${macs[@]}"; do
    [[ "$(normalize_mac "$mac")" == "$gw_mac" ]] && return 0
  done
  return 1
}

# Echo the real utunN device backing a wg-quick interface, or return non-zero if
# it is not up.  wg-quick on darwin records the mapping in /var/run/wireguard.
iface_realdev() {
  local f="/var/run/wireguard/$1.name"
  [[ -f "$f" ]] || return 1
  cat "$f"
}

# Decide whether the tunnel is actually carrying traffic.
tunnel_healthy() {
  local dev="$1" hs now age
  # Authoritative liveness: can we reach the server's in-tunnel address?
  if "$PING" -c 1 -t 3 "$TUNNEL_PROBE_IP" >/dev/null 2>&1; then
    return 0
  fi
  # Tolerate a single dropped probe if the last handshake is still fresh
  # (persistentKeepalive refreshes it roughly every 25s).
  hs="$(wg show "$dev" latest-handshakes 2>/dev/null \
    | awk '{ print $2 }' | sort -nr | head -n1 || true)"
  [[ -n "$hs" && "$hs" != "0" ]] || return 1
  now="$(date +%s)"
  age=$(( now - hs ))
  (( age < HANDSHAKE_MAX_AGE ))
}

# Exponential backoff (5s, 10s, 20s, ... capped at 300s) keyed on the number of
# consecutive bring-up/restart attempts.  This is the guard against a self-
# repair loop thrashing the tunnel when the endpoint is genuinely unreachable.
backoff_seconds() {
  local count="$1" exp secs
  exp="$count"
  (( exp > 6 )) && exp=6
  secs=$(( 5 * (1 << exp) ))
  (( secs > 300 )) && secs=300
  printf '%s' "$secs"
}

backoff_ok() {
  local f="$STATE_DIR/backoff" now last count secs
  now="$(date +%s)"
  last=0
  count=0
  if [[ -f "$f" ]]; then
    read -r last count < "$f" || true
  fi
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  secs="$(backoff_seconds "$count")"
  (( now - last >= secs ))
}

record_attempt() {
  local f="$STATE_DIR/backoff" now last count
  now="$(date +%s)"
  last=0
  count=0
  if [[ -f "$f" ]]; then
    read -r last count < "$f" || true
  fi
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  printf '%s %s\n' "$now" "$(( count + 1 ))" > "$f"
}

reset_backoff() {
  rm -f "$STATE_DIR/backoff"
}

ensure_up() {
  local name="$1"
  if ! backoff_ok; then
    log "in backoff window; deferring bring-up of $name"
    return 0
  fi
  record_attempt
  log "bringing up $name"
  wg-quick up "$name" || log "warning: wg-quick up $name failed"
}

# Recovery is a full down/up, not a partial `wg set`: down/up re-resolves the
# endpoint hostname and reinstalls the /32 endpoint route via the *current*
# physical gateway, which is exactly what goes stale after roaming/wake.
restart() {
  local name="$1"
  if ! backoff_ok; then
    log "in backoff window; deferring restart of $name"
    return 0
  fi
  record_attempt
  log "restarting $name (down/up rebuilds the endpoint route)"
  wg-quick down "$name" >/dev/null 2>&1 || true
  wg-quick up "$name" || log "warning: wg-quick up $name failed"
}

bring_down() {
  local name="$1"
  log "bringing down $name"
  wg-quick down "$name" || log "warning: wg-quick down $name failed"
}

main() {
  mkdir -p "$STATE_DIR"

  # Serialize concurrent runs (a timer tick racing an event).  mkdir is atomic;
  # a lock older than 5 minutes is treated as stale and stolen.
  local lock="$STATE_DIR/reconcile.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    local now lock_mtime age
    now="$(date +%s)"
    lock_mtime="$("$STAT" -f %m "$lock" 2>/dev/null || echo 0)"
    age=$(( now - lock_mtime ))
    if (( age < 300 )); then
      log "another reconcile holds the lock; skipping"
      return 0
    fi
    log "stealing stale lock (${age}s old)"
  fi
  trap 'rmdir "$lock" 2>/dev/null || true' EXIT

  if at_home; then
    log "on home LAN; ensuring tunnel is down"
    iface_realdev "$SPLIT_IFACE" >/dev/null 2>&1 && bring_down "$SPLIT_IFACE"
    iface_realdev "$FULL_IFACE" >/dev/null 2>&1 && bring_down "$FULL_IFACE"
    reset_backoff
    return 0
  fi

  # Roaming.  Pick the profile from the mode file (default: normal/split).
  local mode desired other
  mode="$(cat "$STATE_DIR/vpn-mode" 2>/dev/null || echo normal)"
  if [[ "$mode" == "travel" ]]; then
    desired="$FULL_IFACE"
    other="$SPLIT_IFACE"
  else
    desired="$SPLIT_IFACE"
    other="$FULL_IFACE"
  fi

  # Never leave the non-desired profile up.
  iface_realdev "$other" >/dev/null 2>&1 && bring_down "$other"

  # Bring the desired profile up if it isn't already.
  local dev
  if ! dev="$(iface_realdev "$desired")"; then
    ensure_up "$desired"
    return 0
  fi

  # It is up — health-check it.
  if tunnel_healthy "$dev"; then
    log "$desired healthy"
    reset_backoff
    return 0
  fi

  # Up but unhealthy.  Only churn the tunnel if the physical path is alive;
  # otherwise there is nothing to fix and a restart would just thrash.
  local pg gw
  pg="$(physical_gateway || true)"
  if [[ -n "$pg" ]]; then
    gw="${pg##* }"
    if "$PING" -c 1 -t 1 "$gw" >/dev/null 2>&1; then
      log "$desired unhealthy; physical gateway reachable — restarting"
      restart "$desired"
      return 0
    fi
  fi
  log "$desired unhealthy but no physical connectivity; leaving as-is"
}

main "$@"
