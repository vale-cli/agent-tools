---
name: ci
description: Run Vale in GitHub Actions, a pre-commit hook, or another runner. Use when the user says "add vale to CI", "run vale on PRs", "add a pre-commit hook", or "make the build fail on style errors".
---

# Put Vale in the pipeline

## When to use this

Vale runs locally and should now run automatically.

## Prerequisites

1. `vale ls-config` resolves, and a plain `vale <path>` run works locally. Do
   not wire up CI for a config that does not resolve — the failure will look
   like a CI problem.
2. The user has said whether the job should block. Ask if not.

## Advisory or blocking

**Only `error` sets a non-zero exit code.** Warnings and suggestions exit 0, so
a job wired up naively passes no matter how much it reports.

- **Advisory** — Vale reports, the job stays green. The right way to adopt Vale
  on a corpus that has never had it.
- **Blocking** — the rules the team cares about are set to `error` in the
  config, and the job fails on those.

Say which one you are setting up, in those words. "It runs in CI" tells nobody
whether it can stop a merge.

## GitHub Actions

```yaml
name: Vale
on: [pull_request]

jobs:
  vale:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: vale-cli/vale-action@v3
        with:
          files: docs
```

Three defaults make this safe to add to a repository with a backlog, and they
are worth saying to the user because they answer the first objection:

- **Only lines the pull request adds are reported** (`filter_mode: added`).
  The existing backlog never appears on someone's unrelated change.
- **The job passes whatever Vale finds** (`fail_on_error: false`). That is
  advisory.
- **Alerts with a known fix are offered as suggested changes** a reviewer can
  commit from the pull request.

To make it blocking, add `fail_on_error: true`: the job then fails on an
`error`-level alert in the added lines, and only on those. To get inline
review comments rather than check annotations, set
`reporter: github-pr-review`.

AsciiDoc and reStructuredText need their parser installed in the job first
(`asciidoctor`, `docutils`). Use a release tag for the action, not a branch
name: a branch moves without notice. If the repository already has a Vale
job, update that one — an old `errata-ai/vale-action@v1` step is the same
action under its previous name.

## pre-commit

```yaml
repos:
  - repo: https://github.com/vale-cli/vale
    rev: v3.27.0
    hooks:
      - id: vale
```

Pin `rev` to a release — check <https://github.com/vale-cli/vale/releases>
for the current one rather than copying this number. Hooks that float break at the worst time.

## Any other runner

```bash
vale --no-global --output=line docs/
```

`--output=line` gives `path:line:col:rule:message`, which most CI systems can
turn into annotations. `--no-global` keeps a config on the machine from
changing the result.

If the runner has no cached `StylesPath`, `vale sync` has to run first — and
that means a style updating upstream can fail a build nobody changed. Pin
`Packages` to a release URL rather than a moving reference.

## Do not

- **Do not add `--no-exit` to make a failing job pass.** If those alerts should
  not block, change the levels in the config, where the decision is visible to
  the team.
- **Do not raise `MinAlertLevel` in CI only.** A config that reports different
  things locally and in CI is how people stop trusting the tool.
