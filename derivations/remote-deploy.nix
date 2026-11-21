{
  gawk,
  git,
  openssh,
  rsync,
  writeShellApplication,
}:
writeShellApplication {
  name = "remote-deploy";
  runtimeInputs = [
    gawk
    git
    openssh
    rsync
  ];
  text = builtins.readFile ../scripts/remote-deploy;
}
