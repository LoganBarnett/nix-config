################################################################################
# gpauth derivation vendored from nixpkgs-unstable and adapted to read its
# version/hash/cargoHash from static.nix so the rapid-updater workflow
# (scripts/gpclient-update) can bump it without touching this file.
#
# Upstream packaging history relevant to this vendored copy:
#   - 2.5.0 began statically linking OpenConnect via a git submodule.  Source
#     fetching now requires fetchSubmodules so crates/openconnect/deps/* is
#     populated; without it the build.rs patch step fails.
#   - 2.5.x relocated several hardcoded paths the gpclient companion patches
#     out (see ./gpclient/default.nix).  gpauth itself does not need those
#     substitutions.
#
# Bumping target: 2.5.2 carries the upstream "fix auth callback data parsing"
# and "preserve GlobalProtect cookie fields on reconnect" changes that we are
# trying to pick up.  See README.org §Rapid Package Updates.
################################################################################
{
  rustPlatform,
  lib,
  fetchFromGitHub,
  openssl,
  pkg-config,
  perl,
  webkitgtk_4_1,
  stdenv,
  version,
  hash,
  cargoHash,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gpauth";
  inherit version;

  src = fetchFromGitHub {
    owner = "yuezk";
    repo = "GlobalProtect-openconnect";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true;
    inherit hash;
  };

  buildAndTestSubdir = "apps/gpauth";

  inherit cargoHash;

  nativeBuildInputs = [
    perl
    pkg-config
  ];
  buildInputs = [
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    webkitgtk_4_1
  ];

  meta = {
    changelog = "https://github.com/${finalAttrs.src.owner}/${finalAttrs.src.repo}/blob/${finalAttrs.src.rev}/changelog.md";
    description = "CLI for GlobalProtect VPN, based on OpenConnect, supports the SSO authentication method";
    homepage = "https://github.com/${finalAttrs.src.owner}/${finalAttrs.src.repo}";
    license = lib.licenses.gpl3Only;
    platforms = with lib.platforms; linux ++ darwin;
  };
})
