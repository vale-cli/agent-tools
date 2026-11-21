---
name: ci
description: Run Vale in GitHub Actions, a pre-commit hook, or another runner. Use when the user says "add vale to CI", "run vale on PRs", "add a pre-commit hook", or "make the build fail on style errors".
allowed-tools: Bash(sh ${CLAUDE_SKILL_DIR}/scripts/ci.sh *)
---

# Put Vale in the pipeline

## When to use this

Vale runs locally and should now run automatically.

## Prerequisites

1. `vale ls-config` resolves, and a plain `vale <path>` run works locally. Do
   not wire up CI for a config that does not resolve — the failure will look
   like a CI problem.
2. The user has said whether the job should block. Ask if not.

## Start from the script

`scripts/ci.sh`, beside this file, sees what is already there and prints the
files, so the YAML is not written from memory:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/ci.sh detect
sh ${CLAUDE_SKILL_DIR}/scripts/ci.sh action -f docs                      # the defaults
sh ${CLAUDE_SKILL_DIR}/scripts/ci.sh action -s changed-files -x error -f docs
sh ${CLAUDE_SKILL_DIR}/scripts/ci.sh pre-commit -f docs
```

`detect` reports whether this is a GitHub repository, any workflow that
already runs Vale with its action version, mode and trigger, and whether
pre-commit is in use and has Vale in it. `action` prints a workflow for
`.github/workflows/vale.yml`, adding the Asciidoctor or docutils step when
the config lints those formats. `pre-commit` prints a whole
`.pre-commit-config.yaml`, or only the entry to add when one exists, pinned to
the installed Vale. Each also says, in a line, what the result will do.

It prints and never writes. Read what it printed, say what will change, then
save it. `${CLAUDE_SKILL_DIR}` is the directory this file is in; if it reaches
you as literal text, use that path. The sections below explain what the
output means and cover runners the script does not.

## Ask how it should behave

A check has four settings a team has opinions about. Ask them, in plain words,
with the default first — as multiple-choice questions if your client has a
way to ask those, otherwise as one short message. Skip any the user already
answered, and do not ask about flags by name.

| Ask | Choices (default first) | Flag |
|---|---|---|
| What should it look at on a pull request? | Only the lines it adds · every alert in the files it touches · everything, every time | `-s new-lines` · `changed-files` · `everything` |
| What should it report? | Every alert · warnings and errors · errors only | `-l suggestion` · `warning` · `error` |
| When should it fail? | Never, only report · on errors · on warnings too | `-x never` · `error` · `warning` |
| How should it show up? | Annotations on the check · review comments with one-click fixes | (none) · `-r` |

## What to say about each choice

When the user asks about a choice:

- **Only added lines** is what lets a repository with a backlog adopt Vale:
  nobody is told about text they did not write. **Changed files** suits a
  team working the backlog down as they go: touch a page, clean the page.
  **Everything** shows the whole backlog on every pull request, and is rarely
  wanted except for a small, already-clean docs set.
- **Review comments** cannot be posted on pull requests from forks, so an open
  source project usually keeps annotations.
- **Failing on warnings** only makes sense once the warnings are at zero.

For a pre-commit hook the scope is not a choice: it only ever sees the files
being committed. Its two settings are the level that stops a commit (`-l`,
errors by default) and whether it runs before each commit or before a push
(`-P`).

The `vale-onboard` plugin asks the same four as buttons, in its setup pane and
in `/vale-checks`, with the generated file shown as each one changes. If a
message arrives beginning "Set up where Vale runs in this repository", those
are the answers: run the commands it gives and do not ask again.

## Which runner to offer

- **A GitHub repository** — the action. It is the one that reaches every
  contributor without anyone installing anything.
- **A repository that already uses pre-commit** — the pre-commit entry too.
  Do not introduce pre-commit to a team that does not use it just for this;
  offer it, and say each contributor has to run `pre-commit install`.
- **Both** is fine and common: pre-commit catches it before the push, the
  action catches what skipped the hook.

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

## GitHub Actions: beyond the defaults

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
fetches the grammars and models itself — they are not committed.
Use a release tag for the action, not a branch name: a branch moves without
notice. If the repository already has a Vale
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
