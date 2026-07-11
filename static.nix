################################################################################
# This file contains static definitions for things I expect to be essentially
# hardcoded but easy to update programmatically.
#
# For example, Signal Desktop frequently gets expired.  I don't want to
# constantly update my nixpkgs references and thus have to do lots of major,
# risky rebuilds.  So I need something that defines the specifics I need for
# `signal-desktop` (the URL and hash), and then a script can go in and update
# those on demand.
################################################################################
{

  discord = {
    darwin = {
      version = "0.0.384";
      hash = "sha256-vAp991ilLVviievPZHGFuyi/zMMpDoApjnNTGkXYbwo=";
    };
    linux = {
      version = "0.0.132";
      hash = "sha256-DDt/zr+9sfvyPYUMKCXqEsRvk7wZaxbw2eCWlwxcVec=";
    };
  };

  # Claude Code 2.1.x ships as a native binary per platform instead of a
  # Node.js bundle.  Each platform has its own npm package with a single
  # compiled executable.
  claude-code = {
    version = "2.1.159";
    aarch64-darwin.hash = "sha256-8zMTEk1RGEKnR7F/0V8Bo091Zrz4dsCJ6Gb1Ig4j9cg=";
    x86_64-darwin.hash = "sha256-fN1ajWRBCuNpbJJWJp6fpuKuucaY9ad2EniZQdpH/XM=";
    x86_64-linux.hash = "sha256-ZtdQBprIHTAXG6Bzo/dadR9Zqn9x2zsJ0Qh1G7Ilb48=";
    aarch64-linux.hash = "sha256-jnUSkOW5MVHGnOz2Kp0c4k4cSkT07/u3/oshFaYoM5E=";
  };

  # opencode is built from source via the vendored derivation
  # (../derivations/opencode/default.nix), overridden by overlays/opencode.nix.
  # Pinned independently of nixpkgs because the Emacs client (emacs-opencode)
  # tracks opencode's HTTP API on the latest release, many minor versions ahead
  # of what the pinned nixpkgs ships.  `srcHash` is the fetchFromGitHub hash;
  # `nodeModulesHash` is the bun-install fixed-output hash (both change per
  # release).  Initial values match the vendored master copy.
  opencode = {
    version = "1.17.8";
    srcHash = "sha256-iReCFIJeJIOIs95v0ReVR/X1PnT5dSnR9O0TniyvPR8=";
    nodeModulesHash = "sha256-ERywlcNEF9EUW3JDGH8987g+GAj76RylUtegqMvStyg=";
  };

  # A Bun pinned *only* for building opencode (overlays/opencode.nix passes it
  # via callPackage; the global pkgs.bun is untouched).  opencode 1.17.x's build
  # embeds its web UI through a Bun virtual-module entrypoint that needs a newer
  # Bun than 25.11 ships (1.3.2); this pins the version nixpkgs master builds
  # opencode against.  Bun is distributed only as prebuilt release zips, so this
  # is one flat file hash per platform.
  opencode-bun = {
    version = "1.3.13";
    aarch64-darwin.hash = "sha256-VGfj9l26Umuf6pjwzOBO+vwMY+Fpcz7Ce4dqOtMtoZA=";
    x86_64-darwin.hash = "sha256-qYumpIDyL9qbNDYmuQak4mqlNhi/hdK8WSjs8rpF8O0=";
    aarch64-linux.hash = "sha256-cLrkGzkIsKEg4eWMXIrzDnSvrjuNEbDT/djnh937SyI=";
    x86_64-linux.hash = "sha256-ecB3H6i5LDOq5B4VoODTB+qZ0OLwAxfHHGxTI3p44lo=";
  };

  makemkv = {
    version = "1.18.3";
    # MakeMKV has two components: oss (open source) and bin (proprietary).
    oss = {
      hash = "sha256-vIuwhK46q81QPVu5PvwnPgRuT9RmPTmpg2zgwEf+6CM=";
    };
    bin = {
      hash = "sha256-we5yCukbJ2p8ib6GEUbFuTRjGDHo1sj0U0BkNXJOkr0=";
    };
  };

  # MakeMKV 1.18.x has a firmware flashing bug (100% CPU spin).  This older
  # binary is used solely for the `makemkvcon f` firmware tool.
  makemkv-flasher = {
    version = "1.17.7";
    bin = {
      hash = "sha256-jFvIMbyVKx+HPMhFDGTjktsLJHm2JtGA8P/JZWaJUdA=";
    };
  };

  signal-desktop-bin = {
    version = "8.18.0";
    hash = "sha256-yYf79G8dNy0fAA74R5Qedr+QHZtR1fk90nWBK8f36UM=";
  };

  bgutil-pot = {
    version = "0.8.1";
    x86_64-linux = {
      hash = "sha256-58JkpXT6JwW25dxiKDqKToATDye51+nfROawmqYVGoc=";
    };
    plugin = {
      hash = "sha256-mf2DuY+pOxk9ajtp3HRBDXbnoriJhoxU0WEhyskGA0Q=";
    };
  };

  firefox-bin = {
    version = "148.0.2";
    hash = "sha256-h9yQ8JySvc3Jl402L8Q/zF2Ltyf0nxPy43k65wCNoTI=";
  };

  yt-dlp = {
    version = "2026.03.17";
    hash = "sha256-A4LUCuKCjpVAOJ8jNoYaC3mRCiKH0/wtcsle0YfZyTA=";
  };

  ghostty-bin = {
    version = "1.3.1";
    hash = "sha256-GM/ysKbO6Q7q2cfTBk6AiiUqQLryFKp1LB7LeTuPX2k=";
  };

  zoom-us = {
    version = "7.0.0.77593";
    hash = "sha256-YSUaM8YAJHigm4M9W34/bD164M8f/hbhtcmHyUwFN20=";
  };

  # GlobalProtect VPN client (gpclient + gpauth).  Both vendored derivations
  # (../derivations/gpauth and ../derivations/gpclient) share a single source
  # tarball and Cargo.lock, so one version/hash/cargoHash triplet pins the
  # whole suite.  Pinned independently of nixpkgs because upstream auth and
  # cookie handling fixes land here faster than nixpkgs catches up — see the
  # vendored derivations for packaging notes.
  globalprotect-openconnect = {
    version = "2.5.2";
    hash = "sha256-Eg43O+nu8QWVlRW93QhH1G6IzkZTH4gDeuFhRaasFaQ=";
    cargoHash = "sha256-WAzkVrXxI72FhbPmF9q4b2mKpx53NMSIX/Ze/GvwQdY=";
  };

  # BlackHole 2ch — open-source (GPL-3.0) virtual CoreAudio loopback driver,
  # installed imperatively by darwin-modules/blackhole.nix (NOT via an overlay:
  # it is a notarized .pkg laid into /Library/Audio/Plug-Ins/HAL by Apple's
  # `installer`, with no nixpkgs package to override).  Pinned here rather than
  # treated as evergreen (steam/microsoft-teams) because Existential Audio ships
  # stable, versioned, hashable artifacts AND no self-updater — the version bump
  # has to come from us.  Bump with scripts/blackhole-update.
  blackhole = {
    version = "0.7.0";
    hash = "sha256-pKRK48KolXewRohqVgX3bceKOgimJ9WfIurWD2Q0w3w=";
  };

}
