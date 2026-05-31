################################################################################
# Public stub for the M-CL64PK702X work workstation.
#
# Anything that names HMH/NWEA infrastructure (gateways, tenants, internal
# hostnames, certs, env vars, the home-manager user binding) lives in
# ~/dev/nix-config-hmh-private (gitea.proton:logan/nix-config-hmh-private),
# which extends this configuration via `darwinConfigurations.M-CL64PK702X.
# extendModules { ... }`.  See that repo's hosts/M-CL64PK702X.nix for the rest
# of the configuration.
#
# Also do not include anything that could be a security concern (access routes
# such as ssh, screen sharing, or any remote administration details).
################################################################################
{
  flake-inputs,
  host-id,
  lib,
  system,
  pkgs,
  ...
}:
let
  username = "logan.barnett";
in
{
  services.garage-queue-worker.workers.ollama.settings.capabilities.scalars.vram_mb =
    24576;
  system.primaryUser = username;
  # Something required for every macOS host after a nix-darwin migration.  This
  # value will be different per host.  Perhaps hosts stood up after that point
  # won't need it.
  ids.gids.nixbld = 30000;
  imports = [
    (
      { lib, pkgs, ... }:
      {
        allowUnfreePackagePredicates = [
          (
            pkg:
            builtins.elem (lib.getName pkg) [
              "claude-code"
              "example-unfree-package"
              "terraform"
              "unrar"
              "windsurf"
            ]
          )
        ];
      }
    )
    ../nixos-configs/secrets.nix
    flake-inputs.garage-queue.darwinModules.worker
    flake-inputs.home-manager.darwinModules.home-manager
    ../darwin.nix
    ../darwin-configs/garage-queue-worker.nix
    ../darwin-configs/screen-sharing.nix
    ../darwin-configs/proc-siding-worker.nix
    ../darwin-configs/goss-ollama-metal-gpu.nix
    ../darwin-configs/sonify-health-goss.nix
    ../darwin-configs/ollama.nix
    # M1 Max with 32 GB unified memory: 32 × 0.75 ≈ 24 GB available for
    # model weights when the machine is lightly loaded.
    ../nixos-configs/ollama-models-24gb-vram.nix
    ../nixos-configs/user-can-admin.nix
    ../nixos-configs/workstation.nix
    # user-can-develop.nix lives in nix-config-hmh-private's
    # hosts/M-CL64PK702X.nix.  It pulls in nixos-modules/git-config.nix,
    # which requires a `git-users` module arg; that arg is HMH/NWEA-
    # specific (work email + signing key) and lives only in the private
    # wrapper.  Keeping the import here would make the public host fail
    # to evaluate on its own.
    ../headed-host.nix
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        age.secrets.llm-coding-agent-ssh = {
          generator.script = "ssh-ed25519-with-pub";
          rekeyFile = ../secrets/llm-coding-agent-ssh.age;
          # Allow the primary user to read this key for SSH client usage.
          mode = "0400";
          owner = config.system.primaryUser;
        };
        home-manager.users."logan.barnett" = {
          imports = [
            ../home-configs/ghostty.nix
            ../home-configs/gh-cli.nix
            ../home-configs/copilot.nix
            ../home-configs/ssh-config-general.nix
            ../home-configs/ssh-config-container-vm.nix
            flake-inputs.emacs-config.homeModules.ssh-config-emacs
            ../home-configs/ssh-config-proton.nix
            ../home-configs/tea.nix
          ];
        };
        environment.systemPackages = [
          pkgs.awscli
          # Interact with our internal Bitbucket Data Center server.
          pkgs.bitbucket-cli
          pkgs.confluence-markdown-exporter
          # Command line utility to query, search and tail EL (elasticsearch,
          # logstash) logs.
          pkgs.elktail
          # Use GitHub from the command line.
          pkgs.gh
          # Stop using the cursed GlobalProtect VPN GUI client and use something
          # we can better automate instead.
          pkgs.gpclient
          # Separate authentication tool for GlobalProtect SSO.
          pkgs.gpauth
          # Wrapper script for easy GlobalProtect connection.
          (pkgs.callPackage ../derivations/gp-connect.nix { })
          # Automatic headless authentication for GlobalProtect.
          (pkgs.callPackage ../derivations/gp-connect-auto.nix { })
          # Used for encrypting sensitive information in Hiera.
          pkgs.hiera-eyaml
          pkgs.mktemp
          # Gives us tools like ldapsearch, ldapadd, and ldapmodify which is
          # sometimes used for searching users and figuring out who the managers
          # are of employees.
          pkgs.openldap
          pkgs.openssl
          # Needed for our flavor of Hiera EYAML usage.  See `hiera-eyaml` for
          # more info.
          pkgs.saml2aws
          # Try out terraform changes, including checking on HCP workspaces, which
          # can really speed up coding agent usage.
          pkgs.terraform
          # Let machines write the machine instructions.
          pkgs.windsurf
          # `jq` but for YAML.  The `yq` (no suffix) is a Python app which
          # converts YAML into JSON and then back again if desired.  So it
          # requires `jq` for operations.  This `yq` is standalone and can work
          # with YAML idioms, but isn't as mature as `jq`.
          pkgs.yq-go
        ];
        networking.hostName = host-id;
        nixpkgs.hostPlatform = system;
        security.pki.certificateFiles = [
          "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          # Trust proton CA for local services.
          ../secrets/proton-ca.crt
        ];
        security.pki.keychain.certificateFiles = [
          # Trust proton CA for local services.
          ../secrets/proton-ca.crt
        ];
        system.stateVersion = 5;
        system.activationScripts.postActivation.text = ''
          # Grant SSH access.
          dseditgroup -o edit -a logan.barnett -t user com.apple.access_ssh
          # Set the default shell.  While some systems can work fine without this
          # (I was using Terminal.app just fine while it was broken), things like
          # sshd will silently fail.
          # TODO: Make this work for multiple users.
          # TODO: Contribute this back when multiple activation scripts are
          # allowed.  This either doesn't work, or it isn't enough.  See also the
          # next command.
          echo 'Updating user shells...'
          dscl . -create /Users/logan.barnett UserShell /run/current-system/sw/bin/zsh
          # You'd think we'd just use this, but it's forcibly interactive even
          # when run as root.  Or I'm using it wrong.
          # chsh -u logan.barnett -s /run/current-system/sw/bin/zsh
          echo 'User shells updated.'
        '';
      }
    )
    {
      imports = [
        ../darwin-modules/ollama.nix
      ];
      # services.open-webui.enable = true;
    }
  ];
  networking.monitors = [ "goss" ];
}
