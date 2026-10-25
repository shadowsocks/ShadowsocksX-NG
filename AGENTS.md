# ShadowsocksX-NG

A macOS Shadowsocks client. The legacy implementation has been removed from this repository and archived on the [`legacy-v1`](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1) branch of [shadowsocks/ShadowsocksX-NG](https://github.com/shadowsocks/ShadowsocksX-NG) for read-only reference. The new implementation lives in `ShadowsocksX-NG2/`. Links to legacy source code in documentation and comments must point to that branch.

## Agent skills

### Local validation

When validating ShadowsocksX-NG2 changes or diagnosing local validation artifacts, read the [local validation skill](.agents/skills/shadowsocksx-ng2-local-validation/SKILL.md). The repository copy is maintained; copies with the same name in memory are historical snapshots.

### Git commits

Write commit messages in English using Conventional Commits.

### Issue tracker

Issue tracker configuration is contributor-local.

Before using an issue-tracking skill:

1. Resolve the Git common directory:

   `git rev-parse --path-format=absolute --git-common-dir`

2. Read `<git-common-dir>/agent/issue-tracker.md`.

3. Follow the tracker configuration found there.

If the file does not exist, ask the contributor to
configure their preferred tracker.

Never assume GitHub Issues is the default.
Never commit personal tracker configuration.
Never reference personal tracker issues or tasks in code, commit messages, pull requests, or GitHub comments.

### Triage labels

Use the five default role names as triage label strings: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Use a single context: one root `GLOSSARY.md` plus `docs/adr/`, created on demand. See `docs/agents/domain.md`.

Write the body of `GLOSSARY.md` and new ADRs in Simplified Chinese, retaining code identifiers and necessary English terms. Existing ADRs retain their original language.

Current code, `GLOSSARY.md`, and `docs/adr/` define the current state and accepted designs. Only `GLOSSARY.md` and `docs/adr/` are continuously maintained as current documentation; use current code as the source of truth for implementation behavior. Before using a design document or research report as an implementation basis, verify the relevant descriptions against the code.

`docs/design/` records requirements, designs, and specifications at the time of each task. It is historical reference and does not represent the latest implementation.

`docs/research/` contains research reports. Each report records upstream capabilities, candidate solutions, and conclusions at the time of writing. It does not describe the project's current state or establish that a design has been adopted.

## Contribution Guidelines

Follow the project's CONTRIBUTING.md for all contributions, including AI-assisted development.

