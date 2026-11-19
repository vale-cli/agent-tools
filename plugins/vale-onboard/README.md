# vale-onboard

The Vale onboarding proposal, drawn as a pane beside the chat.

```
/plugin marketplace add vale-cli/agent-tools
/plugin install vale-onboard@agent-tools
/vale-onboard            # or: /vale-onboard docs
```

It tries Microsoft and Google against your docs in a temp directory, opens on
the quieter one, and shows:

- **Package** — a button per package with its alert count. Press one to switch.
- **The table** — the first run, and the run with your choices so far, with a
  bar for how much of the first run is left.
- **Rules** — error-level rules first, then the busiest. Press a rule's button
  to make it quieter: an error becomes a warning, then a suggestion, then off,
  then back to how it shipped. Error-level rules show a real alert from your
  own files underneath.
- **Words spell check does not know** — tick the ones that are right.
  Capitalised words in the body start ticked; lowercase ones and anything in
  the first lines of a file do not, since those are usually typos, inconsistent
  casings or front matter.
- **Not included** — other things Vale can do here, off until ticked.
- **Apply** — puts the baseline you chose in the prompt. Press Enter and Claude
  applies it with the `onboard` skill from the main `vale` plugin, which should
  be installed alongside.

Every press re-runs the preview, so the "With choices" row is a real count, not
an estimate. The current count also sits in the status line, so it stays in
view with the pane closed. Nothing in the repository changes until Claude applies it.

## Experimental

- It is built on Claude Code's function-hook plugin API, which is early access
  and changes between releases.
- It needs `vale` on `PATH` and a POSIX shell (Git Bash on Windows).
- It is for first-time setup. In a repository that already has a `.vale.ini` it
  says so and points to `/vale:tune`.

## Developing

`scripts/` holds copies of the main plugin's preview and survey scripts, since
a plugin is installed on its own. After changing the originals:

```
sh plugins/vale-onboard/sync.sh          # copy them here
sh plugins/vale-onboard/sync.sh --check  # fail if they have drifted
claude plugin validate plugins/vale-onboard
claude plugin test plugins/vale-onboard
```
