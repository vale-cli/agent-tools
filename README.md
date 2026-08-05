# Vale agent tools

Agent skills, a linting hook, and the Vale CMS MCP server, packaged for coding
assistants.

Everything here drives [Vale](https://vale.sh), the prose linter. The skills run
the CLI in your repository — they edit your files and open your pull requests,
and they need no account.

## Requirements

| | |
|---|---|
| **Platforms** | macOS, Linux, and Windows |
| **Skills** | the `vale` binary on `PATH` — [installation](https://docs.vale.sh/topics/installation.md) |
| **Hook** | `vale` and `jq`, plus any POSIX shell |
| **MCP server** | a Vale CMS subscription (see below) |

The hook is POSIX `sh`, verified against `sh`, `bash`, `zsh`, and `dash`. It is
registered in shell form, so Claude Code runs it through `sh -c` on macOS and
Linux and through **Git Bash on Windows**.

**Windows needs Git Bash installed.** Without it Claude Code falls back to
PowerShell, which cannot run a shell script — the hook then does nothing. The
skills and the MCP server are unaffected; they don't shell out.

Each part is independent. No Vale binary and the skills tell you so instead of
guessing; no `jq` and the hook stays quiet; no subscription and everything
except the MCP server still works.

## Install

### Claude Code

```
/plugin marketplace add vale-cli/agent-tools
/plugin install vale@agent-tools
```

Skills are then available as `/vale:setup`, `/vale:fix`, `/vale:triage`,
`/vale:vocab`, and `/vale:ci`, and Claude reaches for them on its own when the
task calls for one.

### Anything else

`skills/` is a plain skills directory, so most clients can read it as-is: copy
the folders you want into wherever your assistant looks for them (for example
`.claude/skills/`, `.cursor/skills/`), or point a skills installer at this
repository.

For a setup with no skill support, hand it <https://vale.sh/AGENTS.md> instead —
it covers the same ground as prose.

## What's in here

### Skills

| Skill | What it does |
|---|---|
| `setup` | Install Vale, write a `.vale.ini` matching the formats actually present, sync styles, and report the first run honestly. |
| `fix` | Fix error-level alerts a file at a time, applying the replacement each rule defines, one pull request per file. |
| `triage` | Turn a first run on an existing corpus into a decision per rule: fix, downgrade, or switch off. |
| `vocab` | Add project terms to a vocabulary so spell check accepts them. |
| `ci` | Wire Vale into GitHub Actions, pre-commit, or another runner — and say whether it blocks. |

Each states its own trigger phrases, checks its prerequisites before touching
anything, and ends with a report. A skill that can't run Vale says so rather
than improvising around it.

### Hook

`hooks/vale-edit.sh` runs on every `Edit` and `Write`. If the file is prose and
the repository has a resolvable Vale config, it lints just that file and hands
any **error-level** alerts back to the assistant to fix before it moves on.

It is silent in every other case — no Vale binary, no `jq`, no config, a file
Vale doesn't lint, or a clean run. Warnings and suggestions are never surfaced;
they're advisory by the project's own choice, and reporting them on every edit
is how people end up turning a linter off.

Requires `vale` and `jq` on `PATH`.

### MCP server

Installing the plugin registers the hosted Vale CMS MCP server at
`https://api.vale.sh/mcp`. It gives an assistant the real engine to check
against, so it can scaffold a rule and then find out whether the thing compiles,
whether the regex matches anything, and whether the config still loads —
`scaffold_rule`, `check_config`, `test_rule`, `diff_rule`, `audit_style`, and
the rest.

**This one is not free.** It needs an active [Vale CMS](https://vale.sh/cms) Pro
or Site subscription, and there's a one-month trial. Claude Code will prompt you
to sign in the first time a tool is called; other clients can paste an MCP token
from Settings in Vale CMS. Until then the server answers with a 401 explaining
exactly that — nothing else in this plugin depends on it, and the skills and
hook work without it.

## How this relates to Vale CMS

[Vale](https://vale.sh) is the free, MIT-licensed linter.
[Vale CMS](https://vale.sh/cms) is a paid hosted product running Vale's engine —
the same twelve check types, the same regex compilation, the same scopes. This
repository sits across both, and the split is worth being precise about, because
it decides what you have to pay for:

| | Runs where | Needs an account |
|---|---|---|
| **Skills** | the `vale` CLI, in your repository | no |
| **Hook** | the `vale` CLI, on your machine | no |
| **MCP server** | Vale CMS, at `api.vale.sh` | yes |

The useful way to hold it: the skills and the hook **consume** styles — they run
rules that already exist and act on the alerts. The MCP server **authors and
verifies** them — it is the only part with an engine on the other end that can
answer whether a rule you just wrote compiles, what it actually matches, and
what it costs to run.

That distinction is why the MCP server is the paid piece. Running a linter is
Vale's job and it is free. Handing an assistant a live engine to check its own
work against is what [Vale CMS](https://vale.sh/cms) is — and it is the same
engine serving the hosted editor there, reached through a different door.

## Development

Load the plugin without installing it:

```
claude --plugin-dir /path/to/agent-tools
```

Then `/reload-plugins` to pick up edits. Validate before pushing:

```
claude plugin validate /path/to/agent-tools
```

## License

MIT
