# DailySpend release data safety

Before preparing any DailySpend version for App Store Connect upload, TestFlight distribution, or App Store release, use the repository skill at `.agents/skills/dailyspend-upgrade-safety/SKILL.md`. Complete its applicable data-safety review and record a version/build-specific release decision before taking the distribution action.

For persistence, migration, iCloud, backup/restore, or storage-identity changes during development, consult the relevant parts of that skill early; perform the full review when preparing the version for release. Ordinary UI edits do not require a full release audit.

Include existing users' upgrade paths, all durable storage and recovery mechanisms, mixed-version devices, and the planned Xcode/macOS 27 and iOS/iPadOS 27 environments while retaining supported older OS coverage. Verify current platform behavior and actual released baselines; do not infer safety from a clean installation or in-memory tests.

Keep existing user data and independent recovery copies intact. Use isolated fixtures and dedicated test accounts for destructive testing. The skill's release gates distinguish known defects from missing evidence and do not authorize production resets, uploads, schema deployments, or private-data access.

Continue authorized local review and fixes until the relevant checks and report are complete. If necessary device, account, or historical-fixture evidence is unavailable, document the exact missing evidence and hold the affected release gate while completing independent work.

# DailySpend quality agent

The project agent is defined in `.codex/agents/dailyspend-quality.toml`. Its reusable workflow is `.agents/skills/dailyspend-quality/SKILL.md`, invoked as `$dailyspend-quality` in Codex, `/dailyspend-quality` in Claude Code, or by asking either tool to use the `dailyspend-quality` agent.

Before preparing each release, use that workflow to review the full feature-to-test matrix, run applicable automated suites, complete the existing upgrade-safety review, critique changed UI/UX using screenshots and interaction evidence, and write a detailed version/build-specific report under `docs/releases/`. Implement meaningful missing automated coverage within authorized development scope; record hardware/account checks separately. Keep upload/restricted-validation and broad-distribution/public-release decisions separate.

During ordinary development, test affected feature behavior and regressions, review changed UI/UX, and summarize upgrade implications. Cosmetic edits alone do not require new unit tests or a full release audit. Do not claim unrun checks passed. Use the workflow directly if custom agent delegation is unavailable.

# Codex and Claude Code

Both tools use the same workflows. The canonical files are this `AGENTS.md`, `.agents/skills/*/SKILL.md` with their references, and `.codex/agents/dailyspend-quality.toml`. Claude Code loads them through thin wrappers: `CLAUDE.md` imports this file, `.claude/skills/<name>/SKILL.md` points to the matching `.agents/skills/<name>/SKILL.md`, and `.claude/agents/dailyspend-quality.md` repeats the Codex agent's instructions verbatim.

Change workflow content only in the canonical files. When a skill's `name`/`description` or the agent's `description`/`developer_instructions` changes, update the matching `.claude/` wrapper in the same change. A new canonical skill needs a new wrapper. `python3 scripts/ci/check_agent_config.py` verifies this and runs in CI. Do not replace wrappers with symlinks; the repository safety check rejects them.

# Development workflow

Follow `docs/DEVELOPMENT_WORKFLOW.md` and `docs/DEFINITION_OF_DONE.md` for human and agent changes. Use issue acceptance criteria, focused branches/PRs, and actual test evidence. Review workflow/build-script changes explicitly. Use only free tools; hosted CI runs only on standard GitHub-hosted runners for public repositories. Do not bypass the private-repository guard, introduce paid runners/services, expose custom secrets or private records, or run untrusted PR code on a personal/self-hosted machine. Debug/Release CI does not clear release data-safety gates.
