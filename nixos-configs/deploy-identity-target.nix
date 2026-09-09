################################################################################
# Accept unattended deployments as root over SSH using the deploy identity.
#
# A host whose wheel group needs a sudo password cannot be deployed through
# --use-remote-sudo without a human typing that password for every remote step.
# Instead, proton-deploy logs in as root with a dedicated key.  Interactive sudo
# keeps its password, and deploys stay unattended.  Root login is key-only and
# the only key is the deploy identity held by hosts importing
# ../agnostic-configs/deploy-identity.nix.  See docs/deploy-identity.org.
################################################################################
{ lib, ... }:
let
  public-key = ../secrets/generated/deploy-key.pub;
  generated = builtins.pathExists public-key;
in
{
  assertions = [
    {
      assertion = generated;
      message = ''
        The deploy identity has not been generated yet.  Run
        `agenix rekey generate --rekey -a` from nix-config-private and commit
        secrets/generated/deploy-key.age and deploy-key.pub.
      '';
    }
  ];
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  users.users.root.openssh.authorizedKeys.keys = lib.optional generated (
    builtins.readFile public-key
  );
}
