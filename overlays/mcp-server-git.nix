################################################################################
# mcp-server-git is packaged only in nixpkgs-unstable — it is absent from the
# 25.11 release branch we track, at every revision, not just the one pinned in
# flake.lock.  Rather than move the whole tree to unstable for one package, we
# instantiate the dedicated nixpkgs-mcp-server-git input and take exactly the
# single attribute from it.
#
# Nothing else is pulled through, so the blast radius of bumping that input is
# this one package.  Delete this overlay and the input together once the
# package lands in the release branch.
################################################################################
{ flake-inputs, system, ... }:
final: prev:
let
  pkgs-mcp-server-git = import flake-inputs.nixpkgs-mcp-server-git {
    inherit system;
  };
in
{
  inherit (pkgs-mcp-server-git) mcp-server-git;
}
