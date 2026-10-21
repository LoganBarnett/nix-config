################################################################################
# bat: a cat clone with syntax highlighting, line numbers, a file header, and
# git added/modified markers in the gutter.
#
# Not aliased over cat.  Invoke it as `bat`.
#
# Highlighting is self-contained: bat embeds a few hundred Sublime Text
# `.sublime-syntax` grammars and `.tmTheme` color themes in the binary.  Nothing
# here depends on an editor being installed.  `bat --list-languages` shows what
# is covered; `programs.bat.syntaxes` is only for adding grammars beyond that
# set, so it is left unset.
################################################################################
{ ... }: {
  programs.bat = {
    enable = true;
    config = {
      # header + grid + line numbers + git change markers.
      style = "full";
      # Theme is left at the default, which picks a dark or light variant of
      # Monokai Extended from the terminal's background.  Terminal.app is not a
      # target, so truecolor themes are fine.  Preview others with
      # `bat --list-themes` and `bat --theme=<name> <file>`.
    };
  };
}
