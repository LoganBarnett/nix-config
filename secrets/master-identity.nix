################################################################################
# The single place that names the agenix master identity files.
#
# As the numbered suffix suggests, the master key can be rotated, so nothing
# else may hardcode these file names.  Both values are file names relative to
# this secrets/ directory.
################################################################################
{
  identity = "agenix-master-key-3.age";
  pubkey = "agenix-master-key-3.pub";
}
