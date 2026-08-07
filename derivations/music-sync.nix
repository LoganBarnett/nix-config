{
  rsync,
  writeShellApplication,
}:
writeShellApplication {
  name = "music-sync";
  # ssh (rsync's transport) deliberately resolves from the ambient PATH so it
  # picks up the user's ssh configuration for silicon.proton.
  runtimeInputs = [ rsync ];
  text = builtins.readFile ../scripts/music-sync;
}
