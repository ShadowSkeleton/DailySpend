"""Synthetic regression tests for the Codex/Claude Code wrapper drift check."""

import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


HELPERS = Path(__file__).resolve().parents[1]
REPOSITORY = HELPERS.parents[1]


def load_helper(name):
    spec = importlib.util.spec_from_file_location(name, HELPERS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


config = load_helper("check_agent_config")


class AgentConfigTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        for relative in ["CLAUDE.md", ".agents", ".codex", ".claude"]:
            source = REPOSITORY / relative
            if source.is_dir():
                shutil.copytree(source, self.root / relative)
            else:
                shutil.copy(source, self.root / relative)

    def tearDown(self):
        self.directory.cleanup()

    def test_repository_wrappers_are_in_sync(self):
        self.assertEqual(config.check(REPOSITORY), [])

    def test_missing_skill_wrapper_is_reported(self):
        shutil.rmtree(self.root / ".claude/skills/dailyspend-quality")
        self.assertIn("missing Claude Code wrapper for skill 'dailyspend-quality'", config.check(self.root))

    def test_changed_skill_description_is_reported(self):
        skill = self.root / ".agents/skills/dailyspend-upgrade-safety/SKILL.md"
        skill.write_text(skill.read_text().replace("description: Review", "description: Audit", 1))
        self.assertIn("skill 'dailyspend-upgrade-safety': wrapper description differs from canonical", config.check(self.root))

    def test_changed_agent_instructions_are_reported(self):
        agent = self.root / ".codex/agents/dailyspend-quality.toml"
        agent.write_text(agent.read_text().replace("Act as", "Behave as", 1))
        self.assertIn("agent 'dailyspend-quality': wrapper instructions differ from developer_instructions", config.check(self.root))

    def test_orphaned_wrapper_is_reported(self):
        orphan = self.root / ".claude/skills/retired-skill"
        orphan.mkdir()
        (orphan / "SKILL.md").write_text("---\nname: retired-skill\ndescription: synthetic\n---\n")
        self.assertIn("skill wrapper 'retired-skill' has no canonical .agents skill", config.check(self.root))

    def test_claude_md_must_import_agents_md(self):
        (self.root / "CLAUDE.md").write_text("# Synthetic\n")
        self.assertIn("CLAUDE.md must exist and import @AGENTS.md", config.check(self.root))


if __name__ == "__main__":
    unittest.main()
