{ git, writeShellApplication }:
writeShellApplication {
  name = "git-tidy";
  runtimeInputs = [ git ];
  text = builtins.readFile ./git-tidy;
}
