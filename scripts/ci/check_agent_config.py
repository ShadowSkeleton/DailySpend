#!/usr/bin/env python3
"""Verify Claude Code wrappers match the canonical Codex agent configuration.

Canonical sources are `.agents/skills/*/SKILL.md` and `.codex/agents/*.toml`.
Claude Code reads `.claude/skills/*/SKILL.md` and `.claude/agents/*.md`, which
must stay thin wrappers. Uses only Python's standard library.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
TOML_STRING = re.compile(r'^(\w+) = "((?:[^"\\]|\\.)*)"$', re.M)
TOML_MULTILINE = re.compile(r'^(\w+) = """\n?(.*?)"""', re.M | re.S)


def frontmatter(text: str) -> tuple[dict[str, str], str]:
    """Return simple `key: value` frontmatter fields and the remaining body."""
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    fields = {}
    for line in text[4:end].splitlines():
        key, separator, value = line.partition(":")
        if separator:
            fields[key.strip()] = value.strip()
    return fields, text[end + 5:]


def codex_agent(text: str) -> dict[str, str]:
    """Read the flat string keys used by `.codex/agents/*.toml`."""
    fields = {key: value for key, value in TOML_MULTILINE.findall(text)}
    for key, value in TOML_STRING.findall(text):
        fields.setdefault(key, value.replace('\\"', '"').replace("\\\\", "\\"))
    return fields


def check(root: Path) -> list[str]:
    problems = []

    claude_md = root / "CLAUDE.md"
    if not claude_md.is_file() or "@AGENTS.md" not in claude_md.read_text(errors="replace"):
        problems.append("CLAUDE.md must exist and import @AGENTS.md")

    canonical_skills = sorted((root / ".agents/skills").glob("*/SKILL.md"))
    wrapper_skills = sorted((root / ".claude/skills").glob("*/SKILL.md"))
    canonical_names = {path.parent.name for path in canonical_skills}

    for source in canonical_skills:
        name = source.parent.name
        wrapper = root / ".claude/skills" / name / "SKILL.md"
        if not wrapper.is_file():
            problems.append(f"missing Claude Code wrapper for skill '{name}'")
            continue
        source_fields, _ = frontmatter(source.read_text())
        wrapper_fields, wrapper_body = frontmatter(wrapper.read_text())
        for key in ("name", "description"):
            if source_fields.get(key) != wrapper_fields.get(key):
                problems.append(f"skill '{name}': wrapper {key} differs from canonical")
        canonical_path = f".agents/skills/{name}/SKILL.md"
        if canonical_path not in wrapper_body:
            problems.append(f"skill '{name}': wrapper must reference {canonical_path}")

    for wrapper in wrapper_skills:
        if wrapper.parent.name not in canonical_names:
            problems.append(f"skill wrapper '{wrapper.parent.name}' has no canonical .agents skill")

    canonical_agents = sorted((root / ".codex/agents").glob("*.toml"))
    agent_names = set()
    for source in canonical_agents:
        fields = codex_agent(source.read_text())
        name = fields.get("name", source.stem)
        agent_names.add(name)
        wrapper = root / ".claude/agents" / f"{name}.md"
        if not wrapper.is_file():
            problems.append(f"missing Claude Code wrapper for agent '{name}'")
            continue
        wrapper_fields, wrapper_body = frontmatter(wrapper.read_text())
        if wrapper_fields.get("name") != name:
            problems.append(f"agent '{name}': wrapper name differs from canonical")
        if wrapper_fields.get("description") != fields.get("description"):
            problems.append(f"agent '{name}': wrapper description differs from canonical")
        if wrapper_body.strip() != fields.get("developer_instructions", "").strip():
            problems.append(f"agent '{name}': wrapper instructions differ from developer_instructions")

    for wrapper in sorted((root / ".claude/agents").glob("*.md")):
        if wrapper.stem not in agent_names:
            problems.append(f"agent wrapper '{wrapper.stem}' has no canonical .codex agent")

    return problems


def main() -> int:
    problems = check(ROOT)
    for problem in problems:
        print(f"Agent configuration drift: {problem}", file=sys.stderr)
    if problems:
        return 1
    print("Codex and Claude Code agent configuration are in sync.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
