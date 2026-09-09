################################################################################
# Hold the deploy identity: the SSH key proton-deploy uses to log into
# deployment targets as root.  Targets accept it by importing
# ../nixos-configs/deploy-identity-target.nix.  See docs/deploy-identity.org.
################################################################################
{ config, facts, ... }:
{
  # The public half lands in secrets/generated/deploy-key.pub, which the target
  # side installs for root.
  age.secrets.deploy-key = {
    generator.script = "ssh-ed25519-with-pub";
    # proton-deploy runs as the deploying user, not as root.
    mode = "0400";
    owner = "logan";
  };
  # Both nixos-rebuild and nix copy shell out to ssh, so a client-side Match
  # block is what routes root logins on the LAN to this key.  IdentitiesOnly
  # keeps the user's own keys from being offered for root.
  home-manager.users.logan.programs.ssh.matchBlocks."deploy-identity" = {
    match = "host *.${facts.network.domain} user root";
    identityFile = config.age.secrets.deploy-key.path;
    identitiesOnly = true;
  };
}
