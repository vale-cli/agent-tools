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

## Workflow: install

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

- Windows: `scripts/install.ps1`, beside this file. It does the same job:
  winget, Scoop or Chocolatey if one is installed, otherwise the verified
  release zip into `%LOCALAPPDATA%\Programs\vale`. `-AddToPath` adds that
  directory to the user's `PATH`; the same rule about asking applies.

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}\scripts\install.ps1"
```

  The other scripts in these skills are POSIX shell and need Git Bash on
  Windows, which Git for Windows installs. If `sh` is not available, say so
  and do their steps by hand with `vale` directly; do not skip them.

`${CLAUDE_SKILL_DIR}` is the directory this file is in; if it reaches you as
literal text, use that path.

If the project already pins its tools, pin Vale the same way instead, so
everyone and CI run one version: `mise use vale@<version>`,
`npm install --save-dev @vvago/vale` (run as `npx vale`), `pip install vale`,
or `conda install conda-forge::vale`. Other routes are at
<https://docs.vale.sh/topics/installation.md>. A missing
binary is not a reason to stop and hand the user a to-do.

## Workflow: configure

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
styles/config/grammars/
styles/config/models/
!styles/<Project>/
```

`styles/config/` holds the vocabularies and dictionaries, and
`styles/<Project>/` is where the project's own rules go — see `tune`.
Ignoring `styles/` outright silently drops them from every commit. The two
lines in the middle matter once the config covers source code or another
language: `vale sync` downloads tree-sitter grammars and language models into
`config/`, megabytes each, and they are build output like the packages.

## Workflow: first run

**6. `vale sync`, then lint one file** to confirm the setup resolves. AsciiDoc
needs `asciidoctor` on `PATH` and reStructuredText needs `rst2html`
(`docutils`); without them Vale stops with an error naming the missing tool.
Install it, and remember the CI job needs it too.

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

## Docs in more than one language

A first config usually leaves translations out. Add a section when the
repository has them.

Translated docs under `docs/fr/`, `i18n/de/`, `content/ja/` should not be read
as English: every word fails spell check and the English style rules mean
nothing. Give each language a section, **after** the general one so it wins:

```ini
[*.md]
BasedOnStyles = Vale, Microsoft

[docs/fr/**/*.md]
Lang = fr
BasedOnStyles = Vale
```

- `Lang` takes the language as a tag: `fr`, `de`, `pt-BR`. `vale sync` then
  installs a sentence and tagging model for French, German and Spanish; other
  languages are read by punctuation.
- `BasedOnStyles = Vale` drops the English style package for those files. Add
  the project's own style back only if its rules make sense in that language.
- Spell check needs that language's dictionary, which Vale does not carry.
  Without one it skips the files and says so. `vocab` has the script that
  installs one.

If there is no dictionary yet, or the team does not want translations
checked, keep the section and add `Vale.Spelling = NO` to it. That records
the language, stops the files being read as English, and is silent — without
it Vale warns about the missing dictionary on every run. Remove the line once
a dictionary is installed.

## Comments in source code

Vale reads the comments in Go, Python, JavaScript, TypeScript, Java, Rust and
about twenty other languages, using a tree-sitter grammar per language so a
`//` inside a string is not mistaken for one. A section naming the extensions
is all it takes; `vale sync` installs the grammars the sections imply.

```ini
[*.{go,py}]
BasedOnStyles = Vale

# Comments are full of identifiers; advisory until the vocabulary catches up.
Vale.Spelling = warning
```

- Start with `Vale` alone. The prose style packages are written for
  documentation and are noisy on comments. The `Comments` package covers
  comment conventions — owned `TODO` comments, commented-out code, doc-comment form.
- Expect identifiers. On one 280-file Go codebase the first run was 567
  spelling alerts in under two seconds, nearly all names: `ctx`, `argv`,
  tool names. That is why spelling starts at `warning` here. Real names go in
  the vocabulary; an identifier mentioned in a comment belongs in backticks,
  which Vale skips.
- This is opt-in. Do not add a code section to a docs setup unasked; offer it.

The languages and their extensions: <https://docs.vale.sh/formats/code.md>.

## A configuration for every project on this machine

Vale also reads one user-level `.vale.ini`, in addition to the project's, on
every run. It suits what belongs to a person rather than a team: rules they
want on their own writing everywhere, or linting files that sit outside any
project. `vale ls-dirs` prints where the file and its styles go.

Offer it only when the user asks for something machine-wide. It is their
file, outside the repository: say what you will write before writing it.

```ini
Packages = write-good

[*.md]
BasedOnStyles = Vale, write-good
```

- Leave `StylesPath` out. The styles then go in the directory `vale ls-dirs`
  names, which every run already searches.
- Sync it by name. A plain `vale sync` inside a project reads the project's
  file only:

```bash
vale --config="<the .vale.ini path from vale ls-dirs>" sync
```

- Where both files set a key, the project's value wins. `BasedOnStyles` for
  the same glob is the exception: the two lists are combined, so a
  user-level style runs in every project that glob matches.
- Nobody else has this file. Anything the team relies on goes in the
  project's `.vale.ini`, and CI runs with `--no-global`. `doctor` reports
  what the user-level file changes in a project.

## Do not

- Do not put a team's rules in the user-level configuration.
- Do not commit synced packages, and do not ignore `styles/config/` or the
  project's own style along with them.
- Do not pick the style package without asking.
- Do not set `MinAlertLevel = error` to make the first run look clean. Nothing
  has been decided by hiding the output.
