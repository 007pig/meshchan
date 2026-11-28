@AGENTS.md

# Claude Code

The shared project instructions are imported from `AGENTS.md` above. Keep
only Claude Code-specific guidance here, and keep Codex-specific guidance out
of `AGENTS.md`.

## Tool mapping

- Where `AGENTS.md` says "subagents", use the Agent tool.
- Where it says "Computer Use" for host UI steps, use the computer-use tools
  when available.

## Skills

- `.claude/skills` is a symlink to `.agents/skills`. Create and edit all
  skills under `.agents/skills/`; there are no Claude Code-only skills.
- Claude Code settings, permissions, hooks, MCP servers and subagents stay in
  `.claude/` and are managed separately from Codex's `.codex/` configuration.
