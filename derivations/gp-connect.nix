{
  bash,
  coreutils,
  gpclient,
  writeShellApplication,
  ...
}:
let
  name = "gp-connect";
  script = name;
in
writeShellApplication {
  inherit name;
  runtimeInputs = [
    bash
    coreutils
    gpclient
  ];
  text = builtins.readFile ../scripts/${script};
}
