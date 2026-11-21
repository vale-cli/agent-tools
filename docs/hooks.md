# Hooks

## The edit hook

`hooks/vale-edit.sh` runs every time **the assistant** writes or edits a file —
not when you do. If that file is prose and the repository has a resolvable Vale
config, it lints that one file and hands the alerts straight back for fixing,
in the same turn. Source files count too, when your config has a section for
them: Vale reads their comments, so a typo in a doc comment is caught the same
way.

It is silent in every other case — no Vale binary, no `jq`, no config, a file
Vale doesn't lint, or a clean run.

### Check it works

Editing a file in your own editor does nothing. To see it, ask Claude to change
a prose file in a repository that has a working Vale config, and watch it get
pulled up on any error-level alert before it moves on.

If nothing happens, that is often correct — by default the hook is silent
unless a file Vale lints has an **error**. Ask for `/vale:doctor`, or check the
setup by hand:

```bash
vale ls-config >/dev/null && echo "config resolves"
vale --no-exit --output=line path/to/file.md   # any `error` lines?
```

No errors there means nothing for the hook to say.

### Which alerts reach Claude

By default, **errors only**. Warnings and suggestions are advisory by the
project's own choice, and reporting them on every edit is how people end up
turning a linter off.

Some styles are deliberately advisory, though, and against those the default
leaves the hook quiet. Run `/plugin` and set **Alert level the edit hook
reports**:

| Value | Relays |
|---|---|
| `error` (default) | errors |
| `warning` | errors and warnings |
| `suggestion` | everything |

The setting is a fixed list of those three. A value from an older settings
file, or a mistyped `VALE_HOOK_LEVEL`, is treated as `error` rather than
turning the hook into an error on every edit.

To override it for one shell or outside the plugin, set `VALE_HOOK_LEVEL`,
which wins over the plugin setting:

```bash
VALE_HOOK_LEVEL=warning claude
```

Two gates apply, in order: Vale's own `MinAlertLevel` decides what appears in
the output at all, and this decides what reaches Claude. Raising the level past
`MinAlertLevel` gains nothing.

Above `error`, each line carries its severity and the closing instruction
changes to match — the errors get fixed, the rest is passed along as advice.

## The commit hook

A second hook, `hooks/vale-commit.sh`, runs after the assistant makes a commit.
If the repository's config has a `[COMMIT_EDITMSG]` section — see
`/vale:commits` — it lints the message git just recorded and hands back any
error-level alerts, with the instruction to amend if the commit has not been
pushed.

A project's own `commit-msg` hook does this for people, but it is installed per
clone, and an assistant's checkout usually has not run the project's setup.
This gives the assistant's commits the same check. Without that section in the
config it does nothing.

## Requirements

The hooks need `vale` and `jq`, plus any POSIX shell. They are plain `sh`,
verified against `sh`, `bash`, `zsh`, and `dash`. On Windows they need Git Bash
(Git for Windows includes it); without it Claude Code falls back to PowerShell,
which cannot run them, so the hooks do nothing.

The [`vale-lsp`](../plugins/vale-lsp) plugin is an alternative to the edit hook:
alerts arrive as diagnostics from Vale's language server. Use one or the other,
not both.
