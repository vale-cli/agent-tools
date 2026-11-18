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

To make it blocking, add `fail_on_error: true`: the job then fails on an
`error`-level alert in the added lines, and only on those.

Set `files:` every time. Its default is the repository root, which lints
whatever the config's sections match, vendored trees included.

**Suggested fixes.** With `reporter: github-pr-review`, alerts arrive as
review comments, and one whose rule carries a fix is offered as a suggested
change the reviewer can commit from the pull request. It is not the default
reporter, and it does not work on pull requests from forks, whose token is
read-only — the default reporter still annotates those. Offer it for
repositories whose contributors push branches; leave the default for open
source projects that take forks.

**Caching.** `vale sync` downloads every package on every run. For a slow or
rate-limited runner, restore the `StylesPath` from a cache keyed on
`.vale.ini` and pass `sync: false` on a hit; the action's README has the
snippet. Not worth adding by default.

AsciiDoc and reStructuredText need their parser installed in the job first
(`asciidoctor`, `docutils`). If the config lints source code or another
language, `files:` has to include those paths, and the job's `vale sync`
fetches the grammars and models itself — they are not committed. Use a release tag for the action, not a branch
name: a branch moves without notice. If the repository already has a Vale
job, update that one — an old `errata-ai/vale-action@v1` step is the same
action under its previous name. Keep its `files:` path. "Only added lines"
needs a pull request to compare against, so a job that runs only `on: push`
should gain `pull_request`; say that you changed the trigger, since it is
their workflow. The action uses the job's own `GITHUB_TOKEN` by default, so an
explicit `env: GITHUB_TOKEN` line from an older setup can go.

## pre-commit

```yaml
repos:
  - repo: https://github.com/vale-cli/vale
    rev: v3.27.0
    hooks:
      - id: vale
        name: vale sync
        pass_filenames: false
        args: [sync]
      - id: vale
        args: [--output=line, --minAlertLevel=error]
```

The first entry runs `vale sync`. Without it the hook fails on any clone that
has not synced, because the styles are not in the repository. The second
reports errors only: a commit hook that prints every suggestion is one people
skip. For commit *messages*, see `commits`.

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
that means a style updating upstream can fail a build nobody changed. If that
matters to the team, an entry in `Packages` can be the URL of a release `.zip`
instead of a name; a name always installs the current version. Leave it as a
name unless they ask.

## Do not

- **Do not add `--no-exit` to make a failing job pass.** If those alerts should
  not block, change the levels in the config, where the decision is visible to
  the team.
- **Do not raise `MinAlertLevel` in CI only.** A config that reports different
  things locally and in CI is how people stop trusting the tool.
