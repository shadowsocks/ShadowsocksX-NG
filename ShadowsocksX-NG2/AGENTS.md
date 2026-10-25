# ShadowsocksX-NG2

See the root [`AGENTS.md`](../AGENTS.md) for repository conventions and [`README.md`](README.md) for project and development documentation.

## Testing principles

- Keep unit tests hostless and access packaged resources through explicit dependency injection.
- Isolate test resources to support parallel execution across multiple runners.
- Choose the smallest deterministic inputs that serve the assertions. When optimizing duration, preserve the tested workflow, scenario relationships, and timing semantics.

Before adding or modifying tests or optimizing test duration, read [Writing and optimizing tests](../docs/development.md#writing-and-optimizing-tests) for framework selection, resource lookup, fixture design, and measurement methods.
