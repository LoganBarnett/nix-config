{
  lib,
  fetchFromGitHub,
  fetchPypi,
  python3,
  ...
}:
let
  pname = "zalgo-cli";
  python = python3;
  version = "0.5.0";
in
python.pkgs.buildPythonApplication {
  inherit pname version;
  format = "pyproject";
  src = fetchFromGitHub {
    owner = "tddschn";
    repo = "zalgo-cli";
    rev = "v${version}";
    hash = "sha256-UOL0UuuXlFmnV+sBuvTJk/CMnmMVurVjkm9CinEcBUw=";
  };
  nativeBuildInputs = [
    python.pkgs.poetry-core
  ];
  # Looks like the current version isn't published to Pypi.
  # src = fetchPypi {
  #   inherit pname;
  #   version = "v${version}";
  # };
  # The project declares gradio as a hard dependency, but only the
  # zalgo-gradio entry point imports it.  nixpkgs' gradio 5 is flagged with
  # known CVEs, so leave it out entirely and skip the runtime dependency
  # check that would otherwise fail on the declared-but-absent package.
  dontCheckRuntimeDeps = true;
  postInstall = ''
    rm "$out/bin/zalgo-gradio"
  '';
  meta = {
    description = "Zalgo text generator CLI.";
    homepage = "https://github.com/tddschn/zalgo-cli";
    license = lib.licenses.mit;
  };
}
