---
name: vocab
description: Add project terms to a Vale vocabulary so spell check accepts them, and set up a regional dictionary when the team wants British, Australian, Canadian or American spelling enforced. Use when the user says "vale doesn't know our product name", "stop flagging this word", "we write in British English", "flag American spellings", or spelling alerts are firing on correct terms.
allowed-tools: Bash(sh ${CLAUDE_SKILL_DIR}/scripts/dictionary.sh -d *), Bash(sh ${CLAUDE_SKILL_DIR}/scripts/import-words.sh *)
---

# Teach Vale a project's own words

## When to use this

`Vale.Spelling` is flagging terms that are spelled correctly for this
project — product names, APIs, jargon.

The alternative someone will otherwise reach for is disabling spell check
entirely, which stops checking every other word in the repository over one
proper noun.

## Prerequisites

1. `vale ls-config` resolves and shows a `StylesPath`.
2. The flagged terms really are the project's spelling. Check the docs or the
   product itself — the vocabulary becomes the reference everyone else follows.

## Workflow: collect the terms

**1. Collect the terms Vale is actually flagging**, rather than guessing:

```bash
vale --output=JSON <path> | jq -r '.[][] | select(.Check == "Vale.Spelling") | .Match' | sort | uniq -c | sort -rn
```

Look at *where* each term is before deciding what it is. A hit on the first
lines of a file is usually front matter: `id: vscode` is a URL, not a
misspelling, and neither the vocabulary nor the prose is the place to fix it.
Leave those fields unlinted, at the top of `.vale.ini`, above any `[section]`:

```ini
# Page ids and slugs are URLs, not prose.
IgnoredScopes = code, tt, kbd, samp, text.frontmatter.id, text.frontmatter.slug
```

Setting `IgnoredScopes` replaces Vale's defaults, which is why the first four
are restated. Every front matter field has a scope named after it.

**Start from a word list the project already has**, if there is one. A
`cspell.json`, a `.wordlist.txt`, a `.spelling` file, `cSpell.words` in VS
Code settings — someone has already decided those terms are right:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/import-words.sh cspell.json > imported.txt
```

It prints `accept.txt` entries for the words Vale's own spell check does not
know, usually a small part of the list, and says how many. Two things it does
on purpose:

- An all-lowercase word becomes `(?i)word`. Those lists ignore case and a
  vocabulary does not: a plain `kubernetes` entry would make Vale flag
  "Kubernetes" as the wrong casing.
- A word with capitals is kept as written, so Vale holds the docs to that
  casing. If that flags a lowercase use the team considers fine, make the
  entry `(?i)` too.

Read the result as you would any list of terms; an old word list collects
typos someone silenced. Keep the old file until the team decides to retire the
other spell checker — that is their call, not part of this.

## Workflow: write the vocabulary

**2. Create the vocabulary.** It lives inside `StylesPath` but is the one part
of it that is yours and survives `vale sync`:

```
styles/config/vocabularies/<Project>/accept.txt
styles/config/vocabularies/<Project>/reject.txt
```

`<Project>` is the product or repository name in one capitalised word —
`Acme`, `Docs`. Not `Vale`, and not the name of a package in use: both are
styles already, and the project's own rules will share this name.

**3. Name it in `.vale.ini`:**

```ini
Vocab = <Project>
```

**4. Add one term per line** to `accept.txt`. The possessive comes free:
accepting `Tengo` accepts `Tengo's`. Entries are case-sensitive
regular expressions, so `Kubernetes` accepts that spelling and not
`kubernetes` — usually what a project wants, because the casing is part of the
name.

**5. Use `reject.txt`** for terms the project has banned: an old product name,
a deprecated spelling. Rejected terms are flagged wherever they appear.

**6. Re-run** and report what is left.

**7. Commit the vocabulary.** Unlike the rest of `StylesPath`, it is source.
Check it is not ignored first:

```bash
git check-ignore -v styles/config/vocabularies/<Project>/accept.txt
```

Any output means a `.gitignore` rule is covering it. Narrow that rule to
`styles/*` with `!styles/config/` rather than forcing the file in.

## Words that are the user's, not the project's

Someone's own name, employer or username gets flagged in every repository they
write in, and does not belong in each project's vocabulary. Those go in a
user-level vocabulary instead. `vale ls-dirs` prints the two locations:

```
<user-level StylesPath>/config/vocabularies/<Name>/accept.txt
```

and, at the top of the user-level `.vale.ini`:

```ini
Vocab = <Name>
```

It is added to each project's own vocabulary, not swapped for it. A project
that must not pick it up starts its own list with `NONE`: `Vocab = NONE,
<Project>`.

Two cautions:

- It is the user's file, outside the repository. Say what you will write.
- Check one project that has its own `Vocab` afterwards. If `vale ls-config`
  there stops with "vocabulary not found", this Vale reads a user-level
  `Vocab` before the project's `StylesPath`: remove the line and upgrade
  Vale first.

Product names and jargon still go in the project's vocabulary, where the
team and CI get them.

## Dictionaries: which English

Vale's built-in dictionary accepts both "color" and "colour". A project gets
no noise from either spelling, and no help keeping to one. If the team wants
one enforced, that takes a regional dictionary.

**1. See which way the docs lean**, before asking anyone:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/dictionary.sh -d <path>
```

```
American spellings: 79   organization (42), color (9), center (4), program (3)
British spellings:  1   centre (1)
Leaning: American. The built-in dictionary is fine; en_US would enforce it.
```

A clear lean with a handful of strays is the case for enforcing: those strays
are the inconsistency. Mixed means ask. No lean means leave it alone.

**2. Install the dictionary** — `en_GB`, `en_AU`, `en_CA`, `en_ZA` or `en_US`
(the built-in dictionary is not `en_US`: it accepts both):

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/dictionary.sh en_GB
```

It puts the Hunspell files in `<StylesPath>/config/dictionaries/`, which is
source: commit them, with the licence file saved beside them.

**3. Add a spelling rule that names it.** Copy `tune`'s
`house/SpellingRegional.yml` to `styles/<Project>/Spelling.yml`, set its
`dictionaries` entry, add `<Project>` to `BasedOnStyles`, and switch the
built-in rule off so a typo is not reported twice:

```ini
# British English throughout.
Vale.Spelling = NO
```

**4. Expect the vocabulary to grow.** A regional dictionary is a general one;
it does not know "plugin", "config" or "linted" as the built-in one does. On
one docs set, unknown terms went from 11 to 84 on switching. Run step 1 of the
workflow again and accept the real ones. Say this cost before switching, not
after.

## Dictionaries: another language

For docs in French, German or any other language, the dictionary is what
makes spell check work at all. Vale carries none, and skips files in a
language it has no dictionary for. Name the language as `Lang` does:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/dictionary.sh fr
```

No spelling rule is needed this time: `Vale.Spelling` uses the dictionary for
whatever `Lang` the section sets. `setup` has the section. The script draws on
a collection of about ninety languages; it has none for Japanese or Chinese,
which Hunspell does not suit. Any Hunspell `.dic`/`.aff` pair placed in
`config/dictionaries/` works the same way.

Each language's names and jargon still need accepting. One vocabulary serves
every language in the project.

`${CLAUDE_SKILL_DIR}` is the directory this file is in; if it reaches you as
literal text, use that path.

## Do not

- **Do not disable `Vale.Spelling`.** One unknown product name is not a reason
  to stop checking the repository.
- **Do not add a misspelling to `accept.txt`** to clear an alert. If the term is
  wrong, fix the prose.
- **Do not switch dictionaries to quiet spell check.** A regional dictionary
  is stricter, not looser.
- **Do not bulk-add every flagged token.** Read the list first; some of them
  are genuine typos, and that is the point of the rule.
