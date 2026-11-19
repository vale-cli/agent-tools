---
name: rule
description: Write a Vale rule for a project's own style and prove it with vale test. Use when the user says "add a rule for", "flag this phrase", "enforce our style guide", "write a vale rule", or wants a house convention checked automatically.
---

# Write a rule and prove it

## When to use this

The project has a convention no installed style checks: a banned phrase, a
preferred term, a heading format. The output is one rule file, its test cases,
and a passing `vale test`.

This is for one convention stated in conversation. Other cases have their own
skill:

- A product name that spell check flags is not a rule. Use `vocab`.
- Heading case, contractions, a preferred term, or a regional spelling already
  has a tested template. Use `tune`.
- A whole written style guide goes through `from-guide`, which sorts every
  statement before writing anything.

## Prerequisites

1. `vale ls-config` resolves and lists the project's styles directory.
2. `vale --version` is v3.24.0 or later, which is where `vale test` arrived.
   On an older version, say so and verify by linting a sample file instead.
3. You have the convention in the user's words, with one sentence that breaks
   it and one that must not. Ask for both if they are missing — the second is
   the one people forget, and it is the one that finds false positives.

## Workflow

**1. Check that no rule already does it.** Search the synced styles before
writing a duplicate:

```bash
grep -ril "<phrase>" styles/
```

If an installed rule covers it at the wrong level, changing the level in
`.vale.ini` is the whole job.

**2. Pick the check type.** Most house rules are one of three:

| the convention | `extends` |
|---|---|
| "never write X" | `existence` |
| "write Y, not X" | `substitution` |
| "this heading or term is cased like so" | `capitalization` |

The rest — `occurrence`, `repetition`, `consistency`, `conditional`, `metric`,
`readability`, `spelling`, `sequence`, `script` — are at
<https://docs.vale.sh/checks/existence.md> and its siblings. Read the page for
the type you choose before writing its keys from memory.

**3. Write the rule in the project's own style folder**, with its cases beside
it. Never under a synced package: `vale sync` overwrites those.

```yaml
# styles/House/Simply.yml
extends: existence
message: "Remove '%s': it tells the reader the step is easy, and it may not be."
level: warning
ignorecase: true
tokens:
  - simply
  - just
tests:
  - name: flags the word
    input: Simply run the installer.
    contains: "'Simply'"
  - name: leaves code alone
    input: Run `just build` first.
    absent: House.Simply
```

Write the message for the writer who will read it in a pull request: what to
do, and why.

**4. Enable the style** if it is new, by adding it to `BasedOnStyles` in the
sections that should have it, and make sure git tracks it:
`git check-ignore -v styles/House/Simply.yml` should print nothing. If it
prints a rule, add `!styles/House/` under `styles/*` in `.gitignore`.

**5. Run the cases.**

```bash
vale test --coverage styles/House
```

A rule that matches nothing loads, runs, and reports success; `--coverage`
fails when a rule produced no alert in any case. Name the directory: without
it, every rule in the synced package counts as untested.

**6. Run it on the real corpus, alone.**

```bash
vale --filter='.Name == "House.Simply"' --output=line <path>
```

Read the hits. Each false positive becomes an `absent` case first and a fix to
the rule second. Report the count before settling the level: a new rule at
`error` with four hundred hits breaks a blocking CI job the day it merges.

**7. Report.**

```
Vale rule
=========
Rule:       styles/House/Simply.yml (existence, warning)
Cases:      4 passed
On docs/:   37 alerts in 12 files, 0 false positives in the 20 read
Enabled in: [*.md]
```

## Do not

- **Do not ship a rule without a case that fires and a case that must not.**
- **Do not start at `error`.** Start at `warning` or `suggestion`, and let the
  team raise it once the backlog is gone.
- **Do not edit a synced style to change its rule.** Switch that rule off in
  `.vale.ini` and write the replacement in the project's own style.
- **Do not reach for `sequence` or `script` first.** A token list covers most
  conventions and is the form the next person can read.
