# vale-lsp

Vale's language server, [`vale-ls`](https://docs.vale.sh/guides/lsp), wired
into Claude Code. After Claude edits a prose file, the server's alerts arrive
as diagnostics, the way a type error does for code.

**Experimental, and separate on purpose.** The main `vale` plugin already
hands alerts back through a shell hook. This does the same job through the
language server, and is here for people who want to try that route — in
particular on Windows, where the hook needs Git Bash and a language server
does not. Install one or the other for edit-time alerts, not both, or every
alert arrives twice.

## Install

1. Put `vale-ls` on your `PATH`: download a build from
   <https://github.com/vale-cli/vale-ls/releases>. `vale` itself must be on
   `PATH` too.
2. In Claude Code:

```
/plugin marketplace add vale-cli/agent-tools
/plugin install vale-lsp@agent-tools
```

3. Ask Claude to edit a Markdown file in a repository with a working Vale
   config. A `Found N new diagnostic issues` line under the edit means the
   server started. If none appears, `/plugin` → **Errors** names what is
   missing.

## What it reports

Errors only, matching the hook's default: the server is started with the
filter `.Level == 'error'`. Warnings and suggestions are advisory by the
project's own choice.

It handles `.md`, `.mdx`, `.markdown`, `.adoc`, `.rst`, `.org` and `.txt`.

## Limits

- Claude Code does not start plugin language servers in cloud sessions, so
  this does nothing there. The hook does.
- It does not install or sync anything. Run `vale sync` yourself.
