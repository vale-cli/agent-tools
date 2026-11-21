---
name: commits
description: Lint commit messages with Vale — pick the convention the history already follows, add the hook that stops a bad commit, and check pull requests in CI. Use when the user says "lint our commit messages", "enforce conventional commits", "add a commit-msg hook", "replace commitlint", or "our commit log is a mess".
allowed-tools: Bash(sh ${CLAUDE_SKILL_DIR}/scripts/history.sh *)
---

# Lint commit messages

## When to use this

The team wants its commit log held to a convention, with the tool that already
lints the docs. Vale's `Commits` package carries the common ones —
Conventional Commits, the seven rules, gitmoji, the Go and kernel styles, a
Jira key — and equivalents of commitlint, gitlint, committed, conform and
commitizen for a team replacing one of those.

This is separate from prose linting. `onboard` names it as an option, with
the history's closest convention; it is added only when the user says so.

## Prerequisites

1. `vale --version` is 3.21.0 or later.
2. `vale ls-config` resolves. If there is no config yet, this skill can write
   one that holds only the commit section; say that is what you are doing.

## Workflow: choose and configure

**1. Read the history before choosing.** `scripts/history.sh`, beside this
file, lints the last fifty commits against each convention in a temp
directory and counts how many fail:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/history.sh
```

```
Convention      failing   most common reason
(core only)        0/14
Conventional      12/14   Conventional.Type (12)
SevenRules         4/14   SevenRules.Capitalize (3)
...
Closest: SevenRules, but 4 of 14 fail. A habit, not yet a convention; ask before enforcing.
```

`${CLAUDE_SKILL_DIR}` is the directory this file is in; if it reaches you as
literal text, use that path. The script takes `-n` for more commits and `-c`
to name the conventions to try.

Read the result three ways, as the script does:

- **Most of the history passes one** — enforce that. It confirms a habit.
- **About half passes** — a habit, not a convention. Show the number and ask.
- **Nothing passes** — the team is choosing a convention, not confirming one.
  That is their decision; offer the two or three closest with their counts.

If the user named a convention, still run it: "Conventional, which 3 of your
last 50 commits follow" is worth saying before a hook starts rejecting
everyone's work.

**2. Add the section** to `.vale.ini`, and `Commits` to `Packages`:

```ini
Packages = Microsoft, Commits

[COMMIT_EDITMSG]
BasedOnStyles = Commits, SevenRules
```

`Commits` is the core every convention shares; the second name is the
convention. Levels and switches work as for any rule, and a limit is set with
a bracket key:

```ini
SevenRules.Limit[max] = 72
Commits.Imperative = error
```

Check a rule's name and its parameters in `styles/<Convention>/` after
`vale sync` rather than guessing them. To spell-check the body as well, add
`Vale` to the list; the project's vocabulary applies.

**3. Try it on a message** before installing anything:

```bash
git log -1 --format=%B | vale --path=COMMIT_EDITMSG
```

## Workflow: install and enforce

**4. Install the hook, in the form the repository already uses.**

- A hook runner is present (`lefthook.yml`, `.husky/`,
  `.pre-commit-config.yaml`) — add Vale there. For the pre-commit framework:

```yaml
repos:
  - repo: https://github.com/vale-cli/vale
    rev: v3.27.0
    hooks:
      - id: vale-commit-msg
```

- None — a tracked hook and one `git config` per clone:

```sh
#!/bin/sh
# script/commit-msg — stops a commit whose message fails the project's rules.
case "$(sed -n '1p' "$1")" in
"Merge "* | "Revert "* | "fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
esac
exec vale --path=COMMIT_EDITMSG < "$1"
```

```bash
chmod +x script/commit-msg
git config core.hooksPath script
```

`core.hooksPath` is per clone and is not shared by committing. Say so, and put
the command where contributors already run setup — a `prepare` script, a
`make setup` target, the contributing guide. If `core.hooksPath` is already
set, add to that directory; do not repoint it.

**5. Add the check in CI.** A hook protects only clones that installed it. In
a pull request job, lint each commit the request adds:

```bash
status=0
for sha in $(git rev-list --no-merges "$BASE..HEAD"); do
  git log -1 --format=%B "$sha" | vale --path=COMMIT_EDITMSG || status=1
done
exit $status
```

The job needs `vale sync` first and a checkout with history
(`fetch-depth: 0`). Advisory or blocking is the same decision as in `ci`.

**6. Keep the package's files out of git.** `vale sync` puts the package's
views and templates in `styles/config/`, beside the vocabularies. They are
build output; add `styles/config/views/` and `styles/config/templates/` to
`.gitignore` unless the project keeps its own there.

**7. Report** the convention, how much of the recent history already passes
it, where the hook lives, what each contributor has to run once, and whether
CI blocks.

## Do not

- **Do not enforce a convention the history does not follow without saying
  the number.** A hook that rejects most of the team's normal messages gets
  removed the same day.
- **Do not rewrite existing history** to make it pass. The rules apply from
  here on.
- **Do not put the hook in `.git/hooks`.** It protects one clone and nobody
  else knows it exists.
- **Do not bypass the hook with `--no-verify`** to get your own commit
  through. Fix the message.
- **Do not start with every rule at `error`.** As with prose: the convention's
  shape blocks, the finer points start as warnings.
