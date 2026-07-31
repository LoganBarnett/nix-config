################################################################################
# Right-click ▸ Scripts ▸ "Add to Lutris" for Windows .exe files in Nautilus.
#
# Installs a shell wrapper (scripts/add-to-lutris) and exposes it as a Nautilus
# Scripts entry.  Selecting it generates a Lutris installer YAML pre-filled with
# the executable, working directory, a shared Wine prefix, and a guessed title,
# then opens Lutris' installer GUI (`lutris --install`) to confirm.
#
# See also home-configs/lutris-gaming.nix, which provides the default Wine
# runtime (wineWowPackages.stagingFull) that the generated entry inherits.
################################################################################
{ pkgs, ... }:
let
  add-to-lutris = pkgs.writeShellApplication {
    name = "add-to-lutris";
    # `lutris` is deliberately NOT a runtimeInput: the wrapper must use the
    # programs.lutris FHS-wrapped `lutris` from PATH (which knows about the
    # Nix-provided Wine runners), not a bare pkgs.lutris that would bypass it.
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.libnotify
    ];
    text = builtins.readFile ../scripts/add-to-lutris;
  };
in
{
  home.packages = [ add-to-lutris ];

  # Any executable dropped here appears under Nautilus' right-click ▸ Scripts
  # submenu.  Nautilus sets the working directory to the browsed folder and
  # passes selected paths via $NAUTILUS_SCRIPT_SELECTED_FILE_PATHS.  The file
  # name is the label shown in the menu.
  home.file.".local/share/nautilus/scripts/Add to Lutris" = {
    source = "${add-to-lutris}/bin/add-to-lutris";
    executable = true;
  };
}
