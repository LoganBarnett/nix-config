{
  coreutils,
  mtools,
  openssh,
  writeShellApplication,
}:
writeShellApplication {
  name = "firmware-host-key-install";
  runtimeInputs = [
    coreutils
    mtools
    openssh
  ];
  text = builtins.readFile ./firmware-host-key-install;
}
