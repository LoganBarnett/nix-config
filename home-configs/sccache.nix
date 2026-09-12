################################################################################
# sccache — shared Rust compilation cache and centralised build directory.
#
# Sits transparently in front of rustc via RUSTC_WRAPPER.  Artifacts are
# shared across all projects that use the same crate version, so dependencies
# like tokio and axum are compiled once rather than once per project.
#
# CARGO_TARGET_DIR routes all cargo build output to a single directory
# (~/.cache/cargo-target) instead of per-project target/ directories, so built
# dependencies are not duplicated across 20+ projects.  That directory only
# ever grows on its own, so a daily launchd agent runs cargo-sweep against it
# and removes artifacts no build has touched in 30 days.  Age rather than a
# size cap is the criterion: a dormant project's artifacts are dead weight
# whether or not the disk is under pressure, and sweeping them costs only a
# recompile that needs no network.  cargo-sweep never touches the crate
# sources under ~/.cargo/registry, and sccache serves most of the recompile
# from its own cache.  The agent's log is rotated by
# darwin-configs/cargo-sweep.nix.
#
# The sccache cache lives at ~/.cache/sccache and is capped at 20 GB; LRU
# entries are evicted automatically when the limit is reached.
#
# To inspect cache statistics: sccache --show-stats
# To clear the cache:          sccache --stop-server && rm -rf ~/.cache/sccache
# To sweep by hand:            cargo sweep --time 30 <any Rust project>
################################################################################
{ pkgs, config, ... }:
let
  cargo-target-dir = "${config.home.homeDirectory}/.cache/cargo-target";
  # cargo-sweep finds the target directory through `cargo metadata`, so it
  # has to be pointed at a Cargo project even though the directory is shared.
  # This inert crate exists solely to be that anchor; pointing at a real
  # checkout under ~/dev would tie the agent to that checkout existing.
  sweep-anchor = "${config.home.homeDirectory}/.local/share/cargo-sweep/anchor";
in
{
  home.packages = [
    pkgs.cargo-sweep
    pkgs.sccache
  ];

  home.sessionVariables = {
    CARGO_TARGET_DIR = cargo-target-dir;
    RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
    SCCACHE_DIR = "${config.home.homeDirectory}/.cache/sccache";
    SCCACHE_CACHE_SIZE = "20G";
  };

  # Session vars above are sufficient for login shells, but `nix develop` /
  # direnv-spawned devshells build a fresh env that strips them, and GUI
  # processes (rust-analyzer under Emacs) never had them.  cargo reads its
  # config.toml regardless of caller env, so the values are duplicated here.
  #
  # The `[env]` table only reaches the processes cargo spawns (rustc, build
  # scripts, `cargo run` binaries); cargo does not consult it for its own
  # output location, which is what `build.target-dir` is for.  Without that
  # key, any cargo started outside a login shell silently writes a
  # per-project target/ directory.
  #
  # Other modules may extend this file via `lib.mkAfter` (e.g.
  # nix-config-private's cargo-privacy.nix appends `[net]
  # git-fetch-with-cli` to honour git insteadOf rules).
  home.file.".cargo/config.toml".text = ''
    [build]
    target-dir = "${cargo-target-dir}"

    [env]
    CARGO_TARGET_DIR   = { value = "${cargo-target-dir}",                             force = true }
    RUSTC_WRAPPER      = { value = "${pkgs.sccache}/bin/sccache",                      force = true }
    SCCACHE_DIR        = { value = "${config.home.homeDirectory}/.cache/sccache",      force = true }
    SCCACHE_CACHE_SIZE = { value = "20G",                                              force = true }
  '';

  # `recursive` materialises a real directory of symlinks rather than a single
  # symlink into the store, so cargo can drop a Cargo.lock there if it ever
  # wants to.
  home.file.".local/share/cargo-sweep/anchor" = {
    source = ./cargo-sweep-anchor;
    recursive = true;
  };

  # home-manager only installs launchd agents on macOS; on other hosts this
  # block is inert.
  launchd.agents.cargo-sweep = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.cargo-sweep}/bin/cargo-sweep"
        "sweep"
        "--time"
        "30"
        sweep-anchor
      ];
      # launchd starts agents with a bare environment.  cargo-sweep shells out
      # to cargo, and cargo must resolve the shared directory without the
      # login shell's session variables.
      EnvironmentVariables = {
        PATH = "${pkgs.cargo}/bin:/usr/bin:/bin";
        CARGO_TARGET_DIR = cargo-target-dir;
      };
      # Missed runs (machine asleep) fire on the next wake, unlike cron.
      StartCalendarInterval = [
        {
          Hour = 3;
          Minute = 30;
        }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/cargo-sweep.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/cargo-sweep.log";
    };
  };
}
