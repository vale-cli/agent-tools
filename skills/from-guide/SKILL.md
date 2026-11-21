---
name: from-guide
description: Turn a team's written style guide into Vale rules, each with test cases taken from the guide's own examples. Use when the user says "enforce our style guide", "turn this guide into rules", "make vale check our writing guidelines", or points at a style guide document, wiki page or pasted list of writing rules.
---

# Turn a written style guide into tested rules

## When to use this

The team already has a style guide — a document, a wiki page, a list in a
README — and wants Vale to enforce it. The output is the project's own style:
one rule per enforceable statement, each linked to the section it came from
and each with tests.

For a single preference stated in conversation ("use title case"), use `tune`.

## Prerequisites

1. `vale ls-config` resolves. If not, `onboard` or `setup` first.
2. `vale test --help` works. Testing is what this skill rests on; on a Vale
   too old to have it, say so and stop rather than writing untested rules.
3. You have the guide's text. A URL you cannot read is not the guide — ask for
   the file or a paste.

## What a guide is made of

Read the whole guide, then sort every statement into one of four piles. Most
guides are about a third each of the first three.

| Pile | Looks like | What happens |
|---|---|---|
| **Already covered** | "Use sentence case." "Avoid passive voice." | A package rule exists. Set its level — see `tune`. No new rule. |
| **A rule** | "Write 'sign in', not 'log in'." "Sentences under 30 words." | Write it, with tests. |
| **Vocabulary** | "Our product is Acme, capital A." | `accept.txt` or `reject.txt` — see `vocab`. |
| **Not checkable** | "Be warm." "Write for a busy reader." "Lead with the outcome." | List it in the report as not enforced. Do not approximate it. |

The fourth pile is not a failure. A rule that pretends to check tone fires on
the wrong sentences, and the team switches the whole style off. Saying
"these six statements need a person" is the honest result.

## Which check fits which statement

| The guide says | Check | Notes |
|---|---|---|
| "Don't use X" | `existence` | `tokens` for words, `raw` with `nonword: true` for punctuation |
| "Write X, not Y" | `substitution` | `swap` maps the wrong form to the right one |
| "No more than N per sentence / paragraph" | `occurrence` | `scope`, `max`, `token` |
| "Pick one spelling and stick to it" | `consistency` | `either` pairs; the first one used wins |
| "Define an acronym before using it" | `conditional` | `first` implies `second` |
| "Headings in sentence / title case" | `capitalization` | package rule, or `tune`'s template |
| "Keep it readable at grade N" | `readability` | |
| "Don't repeat a word" | `repetition` | |

Anything that applies only to headings, lists or table cells takes a `scope`.
The syntax for each is at `https://docs.vale.sh/checks/<name>.md`, and scopes
at <https://docs.vale.sh/topics/scopes.md>. Read the page for the check you are
about to write; do not write the YAML from memory.

`example/`, beside this file, is a complete small case: a guide, the five
rules derived from it, and their thirteen passing tests.

## Workflow: sort and write

**1. Read and sort.** Every statement, in the guide's order, into a pile.

**2. Propose before writing.** One table: the statement in the guide's words,
its pile, and for a rule the check type. Counts at the top — "31 statements:
9 covered by Microsoft, 11 rules, 4 vocabulary, 7 not checkable". Get a yes;
the team may want fewer rules than the guide has sentences.

**3. Write one rule per statement** in `styles/<Project>/`, named for what it
checks (`SignIn.yml`, not `Rule7.yml`):

```yaml
# Guide: Words > Sign in
extends: substitution
message: "Use '%s' instead of '%s'."
link: https://example.com/style-guide#sign-in
level: warning
ignorecase: true
swap:
  'log in|log on': sign in
tests:
  - name: the guide's "don't" example is flagged
    input: Log in to your account.
    contains: "Use 'sign in' instead of 'Log in'."
  - name: the guide's "do" example passes
    input: Sign in to your account.
    want: ''
```

- `link` points at the guide section. The alert then takes a writer straight
  to the reason.
- `message` says what to do, in the guide's own wording where it fits.
- Start at `warning`, or `suggestion` for anything about length or
  frequency. Nothing new starts at `error`.

## Workflow: test and enable

**4. Take the tests from the guide.** A guide's "do" and "don't" examples are
test cases already written by the people who own the rule: every "don't" must
be flagged, every "do" must pass. Where the guide gives none, write one of
each, plus the near miss most likely to be a false positive — a longer word
containing the token, the same text in body rather than a heading.

Assert with `contains` and `want: ''`. A `want` line names the style, so it
breaks if the directory is ever renamed.

**5. Run the tests.**

```bash
vale test --coverage styles/<Project>
```

Name the directory: without it, `--coverage` counts every rule in the synced
package as untested. A rule that loads and matches nothing passes its negative
tests perfectly, which is why coverage is not optional.

**6. Enable the style and count against the real corpus.** Add `<Project>` to
`BasedOnStyles`, check it is tracked by git (`setup` has the ignore rules),
then:

```bash
vale --no-exit --output=line <path> | grep '<Project>\.' | cut -d: -f4 | sort | uniq -c | sort -rn
```

Read ten hits of every rule with more than a handful. Tests show a rule does
what you meant; the corpus shows whether what you meant was right. A rule
flagging hundreds of correct sentences is wrong, not strict — narrow it, add
`exceptions`, and add the false positive as a test.

**7. Keep the guide out of its own way.** A guide quotes the forms it bans, so
it will fail its own rules. Either put the banned forms in code spans, which
Vale skips, or leave the guide out of the linted paths. Say which you did.

**8. Report.**

```
Style guide → rules
===================
Guide:        docs/style-guide.md (31 statements)
Covered:       9  by Microsoft, levels set in .vale.ini
Rules:        11  in styles/Acme/, 34 tests passing, coverage complete
Vocabulary:    4  terms
Not enforced:  7  listed below — these need a person

On docs/: 212 alerts from the new rules
   88  Acme.Filler            read 10: all correct
   61  Acme.SignIn            read 10: all correct
   40  Acme.SentenceLength    suggestion
  ...
```

## Do not

- **Do not write a rule without a failing case and a passing case.** Untested
  YAML that looks right is the thing this skill exists to prevent.
- **Do not invent rules the guide does not state**, however sensible. The
  guide is the team's decision; a rule with no section to link to is yours.
- **Do not approximate a judgment call with a word list.** "Be concise" is not
  a list of banned adverbs.
- **Do not duplicate a package rule.** Two rules for one statement means two
  alerts per mistake.
- **Do not start a new rule at `error`.** It blocks merges on its first day,
  on text written before the rule existed.
- **Do not edit the tests to match the rule.** If the guide's own example
  fails, the rule is wrong.
