{ bundlerApp, ruby_3_3 }:
bundlerApp {
  pname = "hiera-eyaml";
  gemdir = ./.;
  exes = [ "eyaml" ];
  # Ruby 3.4 moved base64 out of the default gems, and hiera-eyaml 3.2.1
  # requires it without declaring it, so every eyaml invocation dies at
  # load under 3.4.  3.3 still ships it as a default gem.
  ruby = ruby_3_3;
}
