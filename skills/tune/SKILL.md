---
name: tune
description: Change one of a project's style choices in plain words — heading capitalization, contractions, "we", passive voice, the Oxford comma, company vocabulary and preferred terms — and write it into the Vale config with its reason. Use when the user says "use title case headings", "allow contractions", "stop flagging we", "always write sign in, not log in", "ban the old product name", or "make this rule block".
---

# Tune a project's style choices

## When to use this

Vale is set up, and the user wants it to match how the team writes. They will
say it as a preference ("we use title case"), not as a rule name. This skill
is the map from one to the other.

`onboard` uses the same table to show these choices in its proposal.

## Prerequisites

1. `vale ls-config` resolves.
2. You know which package the config is based on — the `BasedOnStyles` line.
   The rule names below differ between Microsoft and Google.

## The choices

Each choice is on at some level, or off. Levels mean the same thing
everywhere: `error` blocks a merge, `warning` shows up in review, `suggestion`
is advice.

| Choice | Options | Microsoft | Google |
|---|---|---|---|
| Heading capitalization | sentence case · title case · unchecked | `Microsoft.Headings` (sentence) | `Google.Headings` (sentence) |
| Contractions | use them · avoid them · unchecked | `Microsoft.Contractions` (use; ships at `error`) | `Google.Contractions` (use) |
| "We", "our" | avoid · allow | `Microsoft.We` | `Google.We` |
| "I", "my" | avoid · allow | `Microsoft.FirstPerson` | `Google.FirstPerson` |
| Passive voice | flag · allow | `Microsoft.Passive` | `Google.Passive` |
| Oxford comma | require · unchecked | `Microsoft.OxfordComma` | `Google.OxfordComma` |
| Exclamation points | flag · allow | `Microsoft.ExclamationPoints` | `Google.Exclamation` (ships at `error`) |
| "e.g.", "i.e." | spell out · allow | `Microsoft.Foreign` (ships at `error`) | `Google.Latin` (ships at `error`) |
| Semicolons | flag · allow | `Microsoft.Semicolon` | `Google.Semicolons` |
| Long sentences | flag · allow | `Microsoft.SentenceLength` | — |
| Future tense ("will") | flag · allow | — | `Google.Will` |

A choice the package covers is one line in `.vale.ini`, in the section whose
glob matches the files, with the reason above it:

```ini
# We address the reader as "we" in tutorials.
Microsoft.We = NO

# Agreed in the March docs review: spelled-out Latin is required.
Microsoft.Foreign = error
```

For any other package, read the rule names from `styles/<Package>/` — the file
names are the rule names.

## Choices that need the project's own rule

Four options are the opposite of what the packages check, or something no
package can know. Each has a template in `house/`, beside this file, with its
test cases already in it:

| Option | Template | Also set |
|---|---|---|
| Title-case headings (Chicago or AP) | `house/HeadingsTitle.yml` | `<Package>.Headings = NO` |
| Avoid contractions | `house/NoContractions.yml` | `<Package>.Contractions = NO` |
| Preferred terms ("VS Code, not `VSCode`") | `house/Terms.yml` | — |
| One regional spelling (British, Australian, …) | `house/SpellingRegional.yml` | `Vale.Spelling = NO`, and the dictionary — see `vocab` |

To use one:

1. Copy it to `styles/<Project>/`, where `<Project>` is the project's own
   style name — the vocabulary's name is a good choice.
2. Add `<Project>` to `BasedOnStyles`.
3. Make sure it is tracked: `git check-ignore -v styles/<Project>/Terms.yml`
   should print nothing. If it prints a rule, add `!styles/<Project>/` under
   `styles/*` in `.gitignore`.
4. For `Terms.yml`, replace the example pairs with the project's own, and give
   each pair a test case.
5. Run the tests. A rule that matches nothing loads and passes silently;
   `--coverage` is what catches it:

```bash
vale test --coverage styles/<Project>
```

Name the directory. Without it, `--coverage` also counts every rule in the
synced package as untested and fails.

Anything beyond these four is a new rule, not a tweak. Say so rather than
improvising YAML.

## Company vocabulary

Three different things get called "our vocabulary", and they go in three
places:

| The user says | Where it goes |
|---|---|
| "Stop flagging our product name" | `accept.txt` — see `vocab` |
| "Never write the old name" | `reject.txt` — see `vocab` |
| "Write X, not Y" | `house/Terms.yml`, so the alert says what to write instead |

Accepting a term does two more things: Vale flags its other casings
(`Vale.Terms`), so a name in `accept.txt` needs no pair in `Terms.yml` for
casing alone; and capitalization rules stop flagging it, which is the fix when
a heading rule objects to a product name. On one docs set, accepting three
product names took a sentence-case rule from 12 hits to 4.

## Workflow

**1. Find the choice** in the tables and say it back in the user's words with
the rule beside it: "Headings: title case (`Microsoft.Headings` off, own rule
on)".

**2. Count what it changes** before writing anything:

```bash
vale --no-exit --output=line <path> | grep -c 'Microsoft.Headings'
```

For an option that needs an own rule, the preview script in `onboard`
(`scripts/preview.sh -s <dir>`) shows the count without touching the
repository. A choice that flags
three quarters of the corpus is probably the wrong one — say that. On one docs
set, sentence case flagged 10 headings and title case 75; the corpus had
already decided.

**3. Write it**, with the reason as a comment. If the user gave no reason, ask
for one line; "because Sam said so in #docs" is a fine reason. During
`onboard` there is nobody to ask yet: write what the corpus shows ("52 uses
across the tutorials") and say in the report that these are observations for
the team to replace with their own reasons.

**4. Re-run** and confirm the count moved as expected. An override that
changes nothing is misspelled or in the wrong section, and Vale does not warn
about it.

**5. Report** the choice, the line or file written, and the before and after
count for that rule.

## Do not

- **Do not edit a synced package** to change a rule. `vale sync` overwrites
  it. The override goes in `.vale.ini`; an opposite rule goes in the project's
  own style.
- **Do not leave both rules on.** Title-case and sentence-case rules together
  flag every heading.
- **Do not turn a choice into `error`** without saying that it now blocks, and
  how many existing alerts that makes blocking today.
- **Do not add a term pair without a test.** The test is what shows the
  pattern matches the spelling the user complained about.
