---
name: write-guide
description: Write a human-readable style guide from a project's Vale configuration — what the rules are, which ones block, the project's vocabulary, and why each choice was made — in Markdown, MDX, AsciiDoc, reStructuredText, Org or HTML. Use when the user says "write up our style guide", "document our vale rules", "what does our config actually enforce", or "generate a style guide for contributors".
allowed-tools: Bash(sh ${CLAUDE_SKILL_DIR}/scripts/inventory.sh *)
---

# Write the style guide the config already implies

## When to use this

Vale is set up, and the rules live in `.vale.ini` and YAML that most writers
will never open. The team wants a page a new contributor can read: what we
expect, what will block your pull request, what words we use.

This is `from-guide` in reverse. If the team already has a guide and wants it
enforced, use that one.

## Prerequisites

1. `vale ls-config` resolves and `vale sync` has run — the rules are read from
   `StylesPath`.
2. You know where the guide should live and in which format. Default to the
   format the docs are already written in, beside them.

## What is fact and what is prose

Two halves, kept apart on purpose.

**The facts are read, not recalled.** `scripts/inventory.sh`, beside this
file, lists every rule the config turns on, the level it actually runs at
after overrides, and the comment the project wrote above each override as its
reason:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/inventory.sh           # tab-separated
sh ${CLAUDE_SKILL_DIR}/scripts/inventory.sh -f md     # a table, ready to paste
```

| `-f` | Table written as |
|---|---|
| `md`, `mdx` | Markdown pipe table |
| `adoc` | AsciiDoc table |
| `rst` | reStructuredText `list-table` |
| `org` | Org table |
| `html` | HTML `<table>`, for anything else |
| `tsv` | tab-separated, for your own use |

`${CLAUDE_SKILL_DIR}` is the directory this file is in; if it reaches you as
literal text, use that path. The script needs only a POSIX shell. Use its output for every claim about what is
enforced and at what level. Do not describe a rule from memory of the package;
packages change, and the project may have switched it off.

**The prose is yours to write**, from those facts: grouping forty rules into
five sections a person can hold in their head, and saying each in a sentence.

## Workflow: write

**1. Take the inventory**, and read the vocabulary:
`styles/config/vocabularies/<Project>/accept.txt` and `reject.txt`.

**2. Write the guide in this order.** Short. A guide nobody finishes enforces
nothing.

1. *How this works* — three or four sentences: Vale checks these as you write
   and in CI; errors block a merge, warnings are raised in review, suggestions
   are advice; how to run it locally.
2. *What blocks a merge* — the `error` rules only, each in one plain sentence.
   This is the section people need most, so it comes first.
3. *Style choices* — the decisions teams argue about, in plain words:
   headings, contractions, person, voice. `tune` has the list. Include the
   ones switched **off**, with the reason from the config: "We write 'we' in
   tutorials" is as much house style as any rule.
4. *Words* — the product names and their casing, the terms we do not use, and
   any "write X, not Y" pairs from the project's own rules.
5. *Rule reference* — the table from `inventory.sh`, pasted between markers so
   it can be regenerated without touching the prose:

```markdown
<!-- vale-inventory:start -->
…table…
<!-- vale-inventory:end -->
```

   Use the comment syntax of the guide's format for the markers: `//` lines in
   AsciiDoc, `..` in reStructuredText, `#` in Org, `{/* */}` in MDX.

## Workflow: check

**3. Give examples that are true.** For the project's own rules, the test
cases are the examples: an `input` that is flagged is the "don't", one with
`want: ''` is the "do". For a package rule, write a pair and check it:

```bash
printf '%s\n' 'Simply run the installer.' | vale --ext=.md --no-exit --output=line
```

An example the linter does not actually flag teaches the wrong rule.

**4. Put every "don't" in a code span or code block.** Vale skips code, so the
guide can quote what it bans without failing its own rules.

**5. Lint the guide with the config it describes.**

```bash
vale --output=line <guide>
```

It should pass at `error`, and anything else it reports is worth reading: a
style guide that breaks its own rules is noticed.

**6. Report** where the guide is, how many rules it covers at each level, and
anything in the config with no stated reason — those are the gaps for the team
to fill in, not for you to guess.

## Keeping it current

The reference table is the part that goes stale. To refresh it, re-run
`inventory.sh` and replace what is between the markers; leave the prose alone
unless a rule it describes changed level or was switched off. Say in the guide
which commit the table was generated from.

## Do not

- **Do not state a reason the config does not give.** "Switched off — no
  reason recorded" is accurate. An invented rationale will be quoted back to
  the team as policy.
- **Do not document rules that are off as if they were on**, or leave out the
  ones that block.
- **Do not paste forty rule names as the guide.** The table is the appendix;
  the guide is the five sections above it.
- **Do not copy a package's guidance wholesale.** Link to it. The value of
  this page is what the project chose, not what Microsoft wrote.
