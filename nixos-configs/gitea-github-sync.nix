################################################################################
# Keep the gitea copies of the flake inputs current with GitHub.
#
# nix-config-private rewrites every LoganBarnett GitHub input to gitea.proton so
# unpublished changes can be deployed; this is the other half, so changes that
# land on GitHub first (merged pull requests, pushes from another machine) still
# reach gitea.  Branches follow what the flakes pin: forks list only the branch
# in use.  gms-unlock has no GitHub counterpart and is left out.
#
# The public half of the SSH key must be registered once with the gitea account
# that owns these repositories; see docs/gitea-github-sync.org.
################################################################################
{ config, ... }:
{
  imports = [ ../nixos-modules/gitea-github-sync.nix ];

  age.secrets.gitea-github-sync-ssh-key = {
    generator.script = "ssh-ed25519-with-pub";
  };

  services.gitea-github-sync = {
    enable = true;
    sshKeyFile = config.age.secrets.gitea-github-sync-ssh-key.path;
    repos = {
      agenix.branches = [ "installSecretFn" ];
      agenix-rekey.branches = [ "rust-runtime" ];
      dns-smart-block = { };
      emacs-config = { };
      flake-sync-status = { };
      garage-queue = { };
      hash-color = { };
      hyuqueue = { };
      loku = { };
      metalps = { };
      nix-config = { };
      nix-hapi = { };
      nix-hapi-provider-aruba-cx = { };
      nix-hapi-provider-ldap = { };
      nix-hapi-provider-ntfy = { };
      nix-hapi-provider-porkbun = { };
      nix-remote-builder-doctor = { };
      openhab-flake.branches = [ "add-darwin-devshell-support" ];
      org-dnd = { };
      org-mode.branches = [ "org-lint-include-no-side-effects" ];
      org-wiki = { };
      proc-siding = { };
      rust-template = { };
      sonify-health = { };
      sytter = { };
    };
  };
}
