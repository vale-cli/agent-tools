---
name: doctor
description: Check a Vale setup end to end and say what is working, what is broken, and the command that fixes each thing. Use when the user says "vale isn't working", "why is the hook silent", "is vale set up right", "vale reports nothing", or after cloning a repository that uses Vale.
allowed-tools: Bash(sh ${CLAUDE_SKILL_DIR}/scripts/doctor.sh *), Bash(sh ${CLAUDE_SKILL_DIR}/scripts/doctor.sh)
---

# Check a Vale setup

## When to use this

Something about Vale is not behaving, or someone wants to know a setup is
sound before relying on it. Most Vale problems are silent: a config that lints
nothing, styles that were never synced, a hook with nothing to say. This skill
turns silence into a checklist.

It diagnoses. It does not fix anything without being asked.

## Workflow

**1. Run the check** from the repository root:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/doctor.sh
sh ${CLAUDE_SKILL_DIR}/scripts/doctor.sh docs/guide/install.md   # try a particular file
```

`${CLAUDE_SKILL_DIR}` is the directory this file is in; if it reaches you as
literal text, use that path. The script only reads.

```
ok    vale 3.27.0 at /usr/local/bin/vale
ok    configuration loads: .vale.ini
FAIL  styles named in the configuration are not on disk: Microsoft
      -> vale sync
ok    vocabulary Docs: 12 terms accepted
warn  a run on README.md reports nothing
      -> if that is a surprise, check that a [section] glob in the configuration matches this file
```

It checks, in order: the binary, whether the configuration loads, whether
every style it names is on disk, the vocabulary and whether git tracks it,
whether a real run on a real file works, whether a user-level configuration
changes the result, the markup parsers AsciiDoc and reStructuredText need,
and the hooks.

**2. Report it as it is.** Lead with the `FAIL` lines and their fixes, then
the warnings, then one line saying the rest is fine. Do not turn a warning
into a problem or a clean result into a longer one.

**3. Fix only what the user asks for**, and only what the script named. Each
`->` line is the fix. `vale sync` is safe to run. Anything that edits
`.vale.ini` or `.gitignore` is the team's file: say what you would change.

## What the silent cases usually are

- **"The hook does nothing."** It reports errors only, by default, and only on
  files the assistant edits. A file with warnings and no errors is silence by
  design. The level is a plugin setting.
- **"Vale reports nothing on this file."** No `[section]` glob matches it.
  `vale ls-config` shows the sections; a glob is matched against the path from
  the config's directory.
- **"It worked yesterday."** `StylesPath` is not in git, and a fresh clone or a
  cleaned checkout has no styles until `vale sync` runs.
- **"It passes locally and fails in CI"**, or the reverse. A user-level config
  on one machine is being merged in. The check names the file and gives the
  alert count with and without it; `vale ls-dirs` shows where Vale looks.
- **"Every word is a spelling error."** A file in another language read as
  English, or a dictionary file that is not a dictionary. See `setup` and
  `vocab`.

## Do not

- Do not "fix" a silent hook by widening its level unless the user wants
  warnings on every edit.
- Do not edit the configuration to make a check pass. A missing style is
  synced, not removed from `BasedOnStyles`.
- Do not report a setup as healthy from the first three lines. The run on a
  real file is the check that matters.
