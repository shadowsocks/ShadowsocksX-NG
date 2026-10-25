# Contributing to ShadowsocksX-NG

Thanks for your interest in contributing to ShadowsocksX-NG.

ShadowsocksX-NG2 is a new native macOS client, developed separately from the legacy 1.x application. Work on NG2 takes place in `ShadowsocksX-NG2/` on the `develop` branch. The legacy 1.x source is available on the [`legacy-v1` branch](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1).

## Current contribution status

NG2 is still under development. New GitHub Issues and pull requests are temporarily restricted until the v2 code is stable and officially released, as noted in the [project README](README.md). Until then, use [GitHub Discussions](https://github.com/shadowsocks/ShadowsocksX-NG/discussions) for bug reports, questions, feedback, and feature suggestions. Keep NG2 reports out of unrelated legacy 1.x issues.

The guidelines below describe the contribution process once Issues and pull requests are open. The current restrictions still apply.

## Before proposing a change

Check existing Discussions, Issues, and documentation for related work. Small fixes and documentation improvements usually need less coordination. Discuss substantial features, protocol or configuration changes, system-proxy behavior, security-sensitive changes, and architectural refactoring before starting implementation.

Explain the problem and the behavior you want to change. Maintainers may suggest another approach or decline changes outside the project's scope.

## Development setup

NG2 targets macOS 15 or later on Apple Silicon (arm64). Build and test with the Xcode/Swift toolchain, [Task](https://taskfile.dev/), XcodeGen, and SwiftLint. The [Development, Build, and Testing guide](docs/development.md) lists exact tool versions, prerequisites, and troubleshooting.

From the repository root:

```sh
cd ShadowsocksX-NG2
Scripts/fetch-external-binaries.sh
task gen:prj
task build
```

Fetch and verify external binaries before generating the Xcode project. `project.yml` defines Xcode project configuration and is the source of truth for the generated `.xcodeproj`. Debug builds use ad-hoc signing by default. Ordinary development and unit tests do not require a Developer ID certificate.

## Quality and testing

Keep changes focused and easy to review. Preserve existing behavior unless an intentional change has been agreed upon. Add or update tests when behavior changes, especially for regressions, configuration persistence, networking, process lifecycle, encryption, and system-proxy control.

From the repository root, run:

```sh
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml format:check
```

The default validation sequence runs lint, unit tests, and a Debug build. Run real-process smoke tests separately with `task test:smoke` from `ShadowsocksX-NG2/`. Run the checks relevant to your changes, and explain any checks you skip. CI also runs formatting checks and separate test and smoke-test jobs.

Follow the repository's Swift formatting and SwiftLint configuration. Prefer Swift Testing for new unit tests. Use XCTest when you need its UI-testing or performance APIs. Keep tests deterministic and isolated from real user configurations, credentials, and shared fixed ports. See [the development guide](docs/development.md) for test conventions and validation evidence.

## Architecture and dependencies

Before changing component boundaries or established behavior, read the [project structure guide](docs/project-structure.md), [glossary](GLOSSARY.md), and relevant [architecture decision records](docs/adr/). Check historical design and research documents against the current source code.

Keep the boundaries clear between the SwiftUI app, domain code, background Agent, privileged helper, and bundled external executables. For changes to shared contracts, configuration formats, IPC, credentials, proxy routing, or packaging, describe compatibility and migration implications. Check licenses and provenance for new or updated third-party dependencies and binaries. Follow the [distribution and supply-chain guide](docs/distribution.md) when adding them.

## Pull requests

When pull requests are enabled:

- Target `develop` for NG2 changes unless a maintainer requests another branch.
- Keep each pull request focused on one coherent change, with unrelated refactoring separated where practical.
- Describe the motivation, user-visible impact, implementation, and any compatibility or security considerations.
- Summarize the tests you ran and their results. Explain checks you could not run.
- Include screenshots or recordings for visible UI changes when helpful.
- Link relevant **public GitHub Issues** when applicable; an Issue is not required for every small fix.
- Address review feedback constructively. Maintainers decide whether and when a change is merged.

Use English [Conventional Commits](https://www.conventionalcommits.org/) for commit messages, consistent with [`AGENTS.md`](AGENTS.md).

## Public issue tracking and personal workflows

GitHub Issues is the project's official tracker for public bug reports, feature requests, and contributor coordination when enabled. While Issues are restricted, use GitHub Discussions as described above.

Use any tools you prefer for private planning and task management, including Beads, local Markdown files, or other trackers. The project does not require a particular issue tracker, AI agent, IDE, or worktree workflow. Internal tasks are not public project Issues, do not set project priorities, and do not establish maintainer commitments.

Keep contributor-specific tracker configuration and internal task data out of tracked repository files. Never reference personal tracker issues, task IDs, or internal task links in source-code comments, commit messages, public GitHub Issues, pull requests, or GitHub comments. Use a relevant public GitHub Issue or Discussion as the shared reference. Write a clear, self-contained change description that reviewers can understand without internal task history.

AI-assisted contributions follow the same standards as other contributions. Contributors are responsible for understanding, reviewing, and testing all code and content they propose, and for having the right to submit it. Keep secrets, user data, and confidential information out of external tools and submitted artifacts.

## Security reports

Do not report suspected security vulnerabilities in public Issues or Discussions. If GitHub's private vulnerability reporting mechanism is enabled for this repository, use it. Otherwise, contact the maintainers privately before sharing exploit details. Keep real server credentials, subscription URLs, private keys, and unredacted diagnostic logs out of public reports.

## License and conduct

Contributions must be compatible with the repository's [GNU GPL version 3 license](LICENSE). Submit only code, assets, and dependencies you have the right to contribute. Retain applicable copyright and third-party notices.

Be respectful and constructive. Assume good intent, focus reviews on technical merits, and keep discussions useful to contributors with different levels of experience.

## Further reading

- [Project README](README.md)
- [NG2 developer overview](ShadowsocksX-NG2/README.md)
- [Development and validation](docs/development.md)
- [Project structure](docs/project-structure.md)
- [Architecture decisions](docs/adr/)
- [Signing and distribution](docs/distribution.md)
