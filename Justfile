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
