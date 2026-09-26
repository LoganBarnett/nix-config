{ flake-inputs, lib, ... }:
let
  # dkoontz/minimal-agent-orchestrator ships its Claude Code files as plain
  # markdown; read them verbatim so `nix flake update` is the only upgrade
  # step.
  subagents = "${flake-inputs.minimal-agent-orchestrator}/claude-subagents";
  agent = name: builtins.readFile "${subagents}/agents/${name}.md";
  # Convert from commands to skills, since newer Claude versions have dubious
  # docmentation for commands respecting user-only operations.  Skills are not
  # dubious about this.  Or so Claude tells me.
  command =
    name:
    let
      src = builtins.readFile "${subagents}/commands/${name}.md";
      anchor = "---\nname: ${name}\n";
      patched = "${anchor}disable-model-invocation: true\n";
    in
    assert lib.assertMsg (lib.hasInfix anchor src)
      "${name}.md frontmatter changed upstream; update the anchor";
    builtins.replaceStrings [ anchor ] [ patched ] src;
in
{
  programs.claude-code.agents = lib.genAttrs [
    "planner"
    "developer"
    "developer-review"
    "qa"
    "technical-plan-reviewer"
  ] agent;
  programs.claude-code.skills = lib.genAttrs [
    "orchestrate-plan"
    "orchestrate-task"
  ] command;
}
