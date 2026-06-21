# Contributing

Thanks for helping improve Helix. This guide describes the
expected workflow for contributors.

## Workflow

1. Start from the latest version of the `dev` branch for development work.
2. Keep each pull request focused on one concern.
3. Prefer small, reviewable changes over broad rewrites.
4. Update related documents when requirements, assumptions, dashboard scope, or
   validation steps change.
5. Include source links or enough context for metric and tooling claims to be
   checked later.

## Local Validation

Before opening a pull request:

```sh
./scripts/check-prometheus.sh
./scripts/check-grafana.sh
```

## Pull Requests

- Use a clear title that describes the change.
- Explain why the change is needed, not only what changed.
- Link related issues with `Closes #123` when applicable.
- Keep large research updates split by topic when practical.
- Do not include unrelated formatting, generated files, or refactors.

## Commit Guidelines

- Use concise, descriptive commit messages.
- Group related changes together.

## Issues

Use the bug report template for incorrect, outdated, or unclear documentation.
Use the feature request template for new dashboard ideas, missing metrics, or
workflow improvements. Include enough context for maintainers to understand the
use case, expected behavior, and validation path.

