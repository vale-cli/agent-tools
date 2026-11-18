---
name: setup
description: Install Vale, write a .vale.ini, sync styles, and get a first run. Use when the user says "set up vale", "add vale", "add prose linting", or "lint our docs" in a repository that has no Vale config yet.
---

# Set up Vale in this repository

## When to use this

The repository has no `.vale.ini`, or has one that does not resolve. If a
working config already exists, the user probably wants `fix` or
`triage` instead — check before writing anything.

## Prerequisites

1. `vale ls-config` — if it resolves, a config already exists. Fix what it
   reports rather than starting over, and say that is what you are doing.
2. Know where the prose lives. Ask if it is not obvious.

## Workflow

**1. Install** if `vale --version` fails. Do it rather than asking the user
to, and say that you did:

- Linux or macOS: `scripts/install.sh`, beside this file.

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/install.sh
```

  It uses Homebrew, pacman or snap when one is there and can run without a
  password prompt, so Vale stays up to date. Otherwise it downloads the
  release binary, refuses one that does not match the release's published
  checksum, and puts it in a directory already on `PATH` (`~/.local/bin`,
  `~/bin` or `/usr/local/bin`).

  If none of those is on `PATH`, it installs to `~/.local/bin` and prints the
  line the user's shell needs. Adding that line to their startup file is
  `-p`, and it is their file: say what will be added and to which file before
  running with `-p`. Until a new shell starts, call Vale by the full path the
  script printed.

- Windows: `choco install vale`, `scoop install vale`, or
  `winget install -e --id errata-ai.Vale`.

`${CLAUDE_SKILL_DIR}` is the directory this file is in; if it reaches you as
literal text, use that path. Other routes, including pinning Vale's version in
the project, are at <https://docs.vale.sh/topics/installation.md>. A missing
binary is not a reason to stop and hand the user a to-do.

**2. Find the prose.** `docs/`, `content/`, `*.md` at the root. Do not point
Vale at the whole repository. It does not skip `node_modules` on its own, and
vendored directories, changelogs and generated reference pages produce alerts
nobody will act on. The first run is what decides whether the team keeps it.

**3. Write `.vale.ini`** in the repository root:

```ini
StylesPath = styles
MinAlertLevel = suggestion

Packages = Microsoft

[*.md]
BasedOnStyles = Vale, Microsoft
```

Match the section glob to the formats actually present — `[*.{md,mdx}]`,
`[*.adoc]`, `[*.rst]`. A section that matches nothing lints nothing, and Vale
will not warn you about it.

**4. Ask before choosing the style package.** Microsoft and Google disagree
about things teams care about — contractions, headings, the Oxford comma. It is
their editorial decision, not a default you pick for them. The
<https://vale.sh/explorer> listing has the rest.

**5. Ignore the synced packages, not the whole `StylesPath`.** What `vale sync`
downloads is build output; the project's own vocabulary and rules live in the
same directory and are source:

```gitignore
styles/*
!styles/config/
!styles/<Project>/
```

`styles/config/` holds the vocabularies, and `styles/<Project>/` is where the
project's own rules go — see `tune`. Ignoring `styles/` outright
silently drops both from every commit.

**6. `vale sync`, then lint one file** to confirm the setup resolves.

**7. Report the first run honestly.**

```
Vale setup summary
==================
Config:      .vale.ini  ([*.md] → Vale, Microsoft)
Styles:      styles/ (synced packages gitignored), 1 package synced
First run:   docs/ → 0 errors, 214 warnings, 1,988 suggestions
```

A large corpus commonly produces thousands of suggestions on day one. Say the
number, and offer `triage`. Do not quietly raise `MinAlertLevel` to make
it look smaller.

## Do not

- Do not commit synced packages, and do not ignore `styles/config/` or the
  project's own style along with them.
- Do not pick the style package without asking.
- Do not set `MinAlertLevel = error` to make the first run look clean. Nothing
  has been decided by hiding the output.
