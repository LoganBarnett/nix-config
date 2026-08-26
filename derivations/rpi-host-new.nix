{
  git,
  image-create,
  jq,
  openssh,
  rage,
  writeShellApplication,
}:
writeShellApplication {
  name = "rpi-host-new";
  runtimeInputs = [
    git
    image-create
    jq
    openssh
    rage
  ];
  text = builtins.readFile ../scripts/rpi-host-new;
}
