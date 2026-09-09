{
  jq,
  nixos-rebuild,
  openssh,
  writeShellApplication,
}:
let
  # nixos-rebuild uses ssh:// (legacy nix-store --import/export over SSH pipe)
  # when copying the closure to the build host.  Under load, this protocol
  # fails with "Bad file descriptor".  Patching it to ssh-ng:// uses the Nix
  # daemon protocol instead, which is persistent and reliable.
  #
  # --use-remote-sudo also prefixes the build-host command with sudo, and
  # nixos-rebuild runs that ssh session without a tty.  On a host whose wheel
  # group needs a sudo password this fails before anything is built ("a
  # terminal is required to read the password").  Realising a derivation never
  # needs root, so the build-host branch is patched to skip sudo.  The
  # target-host commands that do need root keep theirs, and nixos-rebuild
  # already gives those a tty so the password prompt reaches the user.
  patched-nixos-rebuild = nixos-rebuild.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      substituteInPlace $out/bin/nixos-rebuild \
        --replace-fail '"ssh://$buildHost"' '"ssh-ng://$buildHost"' \
        --replace-fail 'if [[ "''${useSudo:-x}" = 1 ]]; then' \
          'if false; then # proton-deploy: building never needs root.'
    '';
  });
in
writeShellApplication {
  name = "proton-deploy";
  runtimeInputs = [
    jq
    openssh
    patched-nixos-rebuild
  ];
  text = builtins.readFile ../scripts/proton-deploy;
}
