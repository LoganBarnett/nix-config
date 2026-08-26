{
  coreutils,
  mtools,
  rage,
  writeShellApplication,
}:
writeShellApplication {
  name = "firmware-host-key-add";
  runtimeInputs = [
    # diskutil is a macOS system tool and necessarily comes from the ambient
    # PATH.
    coreutils
    mtools
    rage
  ];
  text = builtins.readFile ./firmware-host-key-add;
}
