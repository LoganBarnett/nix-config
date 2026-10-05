################################################################################
# Persistent terminal sessions for a headless host.
#
# Importing this gives logan dtach-backed sessions through the pts wrapper.  A
# long-running terminal then survives a dropped SSH connection.
################################################################################
{ ... }:
{
  imports = [
    ../nixos-modules/persistent-terminal.nix
  ];

  # Enable persistent terminal sessions with dtach.
  services.persistentTerminal = {
    enable = true;
    users = [ "logan" ];
    shellWrapper = true;
  };

  programs.bash.interactiveShellInit = ''
    # Convenience function to attach to a Claude session.
    claude-session() {
      pts attach claude-main
    }
  '';
}
