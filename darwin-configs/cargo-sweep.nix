################################################################################
# Rotates the log of the cargo-sweep launchd agent that
# home-configs/sccache.nix installs.  launchd does not rotate the files it
# opens for StandardOutPath / StandardErrorPath, so newsyslog does it, the same
# way rust-template's mkDarwinService handles its services.  This lives here
# rather than beside the agent because newsyslog.d is a system path that
# home-manager cannot write.
################################################################################
{ config, ... }:
let
  user = config.system.primaryUser;
in
{
  # Flags: N — no signal on rotation.  The agent exits after each daily run and
  # reopens the log on the next, so nothing keeps a descriptor on the rotated
  # inode.  J — bzip2-compress archived rotations.  Size is in KB (10240 =
  # 10 MB); count is archives retained.
  environment.etc."newsyslog.d/cargo-sweep.conf".text = ''
    # logfilename [owner:group] mode count size when flags
    /Users/${user}/Library/Logs/cargo-sweep.log ${user}:staff 640 5 10240 * NJ
  '';
}
