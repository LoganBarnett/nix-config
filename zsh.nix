# zsh is managed differently by home-manager and therefore not something we
# can easily make into an overlay. We could break this out into a function and
# pull it in elsewhere though.
{ pkgs }:
{
  enable = true;
  autosuggestion.enable = true;
  syntaxHighlighting = {
    enable = true;
  };
  oh-my-zsh = {
    enable = true;
    # TODO: These packages and plugins aren't out of reach necessarily but
    # they require some additional work. See
    # https://github.com/nix-community/home-manager/blob/master/modules/programs/zsh.nix
    # for this module so I know what structures the home-manager-zsh setup
    # expects.
    #customPkgs = [
    #  #pkgs.noreallyjustfuckingstopalready
    #  pkgs.zsh-git-prompt
    #];
    plugins = [
      #"nix"
    ];
    theme = "robbyrussell";
  };
  loginExtra = ''
    # Nix won't assume the system certificate trust, and NIX_SSL_CERT_FILE
    # alone does not cover it, so point curl and friends at the system
    # bundle.  Login shells only; move this to home.sessionVariables if
    # non-login shells ever need it.
    export SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"

    # Warn if CLAUDECODE is set at login.  Claude Code injects CLAUDECODE=1
    # into its subprocess environment; if a launcher (e.g. Alfred) is
    # restarted from within a Claude session it inherits the variable and
    # leaks it into every terminal it subsequently opens.  The interactive
    # guard keeps scripts and non-interactive login shells quiet.
    if [[ -o interactive && -n "$CLAUDECODE" ]]; then
      print -P "%F{yellow}%BWARNING:%b CLAUDECODE=1 is set in this login shell.%f"
      print -P "%F{yellow}  This session was started with CLAUDECODE=1 already in the%f"
      print -P "%F{yellow}  environment.  A likely culprit: a launcher (e.g. Alfred) was%f"
      print -P "%F{yellow}  (re)launched by Claude Code and inherited CLAUDECODE=1 from%f"
      print -P "%F{yellow}  its subprocess environment.%f"
      print -P "%F{yellow}  Fix: restart the launcher from Finder or the Dock.%f"
    fi
  '';
  initContent = ''
    source ${pkgs.zsh-git-prompt}/share/zsh-git-prompt/zshrc.sh
    source ~/.zshrc-customized
  '';
  shellAliases = {
    # -G is BSD, but with Nix we use --color now.
    ls = "ls -aG --color=auto";
    grep = "grep --color=auto";
    b = "bundle exec";
    rlb = "RUBYLIB=lib bundle exec";
    curl-json = "curl -v -H 'Accept: application/json'";

    # git
    gs = "git status";
    gfp = "git push --force-with-lease";
    grc = "git rebase --continue";
    gro = "git restore --ours";
    grt = "git restore --theirs";
    glp = "git log --pretty=format:'%Cred%h%Creset %<(60,trunc)%s %Cgreen%<(12,trunc)%cr %C(bold blue)%<(12,trunc)%an%Creset %C(yellow)%<(20,mtrunc)%d%Creset' --abbrev-commit";
    gbu = "git branch --set-upstream-to=origin/$(git branch --show-current) $(git branch --show-current)";

    # ripgrep
    rgh = "rg --hidden --glob '!.git'"; # Search hidden files.

    # yarn flow management because it happens a lot.
    yf = "yarn flow";
    yfs = "yarn flow stop";
    yfr = "yfs && yf";
  };
}
