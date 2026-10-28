@AGENTS.md

# Claude Code entry points

`AGENTS.md` (imported above) is the shared instruction file for Codex and Claude Code. Edit project rules there, not here.

| Workflow | Canonical source | Claude Code entry point |
|---|---|---|
| Upgrade safety | `.agents/skills/dailyspend-upgrade-safety/` | `/dailyspend-upgrade-safety` (`.claude/skills/dailyspend-upgrade-safety/SKILL.md`) |
| Quality review | `.agents/skills/dailyspend-quality/` | `/dailyspend-quality` (`.claude/skills/dailyspend-quality/SKILL.md`) |
| Quality agent | `.codex/agents/dailyspend-quality.toml` | `dailyspend-quality` subagent (`.claude/agents/dailyspend-quality.md`) |

The `.claude/` files are thin wrappers. Change workflow content only in the canonical files; `scripts/ci/check_agent_config.py` fails when the wrappers drift.
