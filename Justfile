# Prefix for long-running commands.  macOS idle-sleeps mid-operation without
# it; Linux has no equivalent and no need for one.
keep-awake := if os() == "macos" { "caffeinate" } else { "" }

test:
    nix flake check

# `systemctl start` merges with the start job udev already queued, so this
# attaches to a running rip rather than launching a second one — and starts a
# rip if the drive holds an unripped disc.  Exits non-zero if the rip fails.
#
# Ctrl-C only detaches: the rip is owned by systemd on the remote host and
# keeps running, so re-running this recipe re-attaches.  Note the unit is
# `Type=oneshot` with `RemainAfterExit=no`, so it sits in `activating` for the
# whole rip and never reaches `active` — polling `systemctl is-active` would
# report "not running" the entire time, which is why this blocks on the job
# instead.
#
# Both halves run in the background under `wait -n`, which returns as soon as
# *either* finishes.  That covers the two ways this ends: the rip completes and
# `systemctl start` returns, or the connection drops and `journalctl` takes a
# SIGPIPE on its next write.  Whichever went first, the survivor gets killed —
# otherwise an interrupted run strands a waiter on the host, since `systemctl
# start` writes nothing and so never trips over the closed channel on its own.
# The waiter needs `sudo kill`: it is root-owned, so an unprivileged kill is
# rejected and the process leaks.
#
# `ssh -t` would be the more usual answer to the hangup problem, but the pty it
# allocates comes up without ONLCR, which staircases journalctl's output down
# and to the right.  Deliberately no pty here.

# Stream an in-flight MakeMKV rip's progress, exiting when the rip completes.
rip-watch host='silicon.proton' device='sr0':
    {{keep-awake}} ssh {{host}} 'journalctl --unit=makemkv-rip@{{device}}.service --follow --lines=0 --output=cat & journal=$!; sudo systemctl start makemkv-rip@{{device}}.service & waiter=$!; wait -n; status=$?; kill $journal 2>/dev/null; sudo kill $waiter 2>/dev/null; exit $status'

# Report a host's failed units without touching anything.
failed host='silicon.proton':
    ssh {{host}} 'systemctl list-units --state=failed --no-pager; systemctl is-system-running || true'

# Shake a host until its failed units come back, in dependency order.
#
# The worry that an implicit dependency tree makes this hard is right in spirit
# but wrong in mechanism: systemd already resolves *declared* ordering, as long
# as you hand it the whole set at once.  `systemctl start a b c` builds a
# single transaction and orders the jobs inside it by After=/Requires=/BindsTo=,
# so a service that needs its database gets the database first.  Three separate
# `systemctl start` invocations throw that away, because each becomes its own
# transaction with nothing to order against.  Hence one invocation carrying the
# entire list — that is the whole trick.
#
# Two things the transaction engine will not do for us:
#
#   1. A unit that has failed repeatedly is rate-limited by StartLimitBurst,
#      and `start` on it returns "start request repeated too quickly" without
#      even trying.  `reset-failed` clears that counter.  Note the ordering
#      constraint: it has to run *after* the list is captured, because
#      reset-failed is also what empties the failed list.  Capture, then reset,
#      then start.
#   2. Undeclared dependencies are invisible.  If a service genuinely needs DNS
#      but nobody wrote After=unbound.service, systemd has no way to know, and
#      the only cure is trying again once the thing it implicitly wanted has
#      come up.  That is what the passes buy — each one re-derives the failed
#      set from scratch, so a pass only retries what is still broken.
#
# Converges early: a pass that finds nothing failed stops the loop.  Exits
# after printing whatever refused to come back, which is the set worth reading
# a journal for.

# Retry a host's failed units in dependency order until they come back.
revive host='silicon.proton' passes='3':
    {{keep-awake}} ssh {{host}} 'for pass in $(seq 1 {{passes}}); do \
        units=$(systemctl list-units --state=failed --plain --no-legend --no-pager \
                | cut --delimiter=" " --fields=1 | tr "\n" " "); \
        if [ -z "$units" ]; then echo "pass $pass: nothing failed"; break; fi; \
        echo "pass $pass: retrying $units"; \
        sudo systemctl reset-failed $units; \
        sudo systemctl start $units || true; \
        sleep 5; \
      done; \
      echo; echo "=== still failed ==="; \
      systemctl list-units --state=failed --no-pager || true; \
      systemctl is-system-running || true'
