---
name: triage
description: Turn a large first Vale run into a decision per rule — fix, keep, downgrade, or switch off — and write the agreed decisions into .vale.ini. Use when the user says "too many alerts", "where do we start", "vale is too noisy", or has just added Vale to an existing corpus.
---

# Triage a first Vale run

## When to use this

Vale runs, the count is in the thousands, and the question is where to start.
The output of this skill is a decision per rule, written into `.vale.ini` once
the user agrees to it. It does not edit prose — that is `fix`.

## Prerequisites

1. `vale ls-config` resolves.
2. You know which path represents the real corpus, not a subset.

## Workflow: sort the rules

**1. Count by rule, not by file.**

```bash
vale --output=JSON <path> > /tmp/vale.json
jq -r 'to_entries | map(.value[]) | group_by(.Check) | map({check: .[0].Check, n: length, severity: .[0].Severity}) | sort_by(-.n) | .[] | "\(.n)\t\(.severity)\t\(.check)"' /tmp/vale.json
```

Decide the rules that carry the volume — usually the top ten. The tail stays
as it is, and the report says so.

**2. Report the shape before proposing anything**: total, the split by
severity, and the ten rules responsible for the most. A team that hears
"18,000 alerts" reaches for `MinAlertLevel`; a team that hears "four rules are
80% of this" makes a decision.

**3. Sort each of the top rules into one bucket, and say which and why:**

| bucket | when | what to write |
|---|---|---|
| **Fix** | few hits, rule is right | nothing in the config; do it now, or hand to `fix` |
| **Keep** | rule is right and already advisory | nothing; it guides new writing and blocks nothing |
| **Downgrade** | rule is right, backlog is real, level is `error` or `warning` | a lower level, *with a comment saying why* |
| **Disable** | rule does not match how this project writes | `NO`, *with a comment saying why* |

A rule already at `suggestion` cannot be downgraded — it is at the lowest
level. The choice there is keep or disable, and calling it a downgrade changes
nothing.

## Workflow: decide and write

**4. Say what blocks.** Only `error` exits non-zero, so a
pipeline can adopt Vale immediately with everything else advisory. That is usually the
right first move and worth stating outright.

**5. Show the plan and get a yes before touching the config.** Levels are the
team's editorial decision. Present the buckets, the reason for each, and the
exact lines you intend to add.

**6. Write the decisions into `.vale.ini`.** Overrides go in the section whose
glob matches the files, below `BasedOnStyles`, one rule per line with its
reason above it:

```ini
[*.md]
BasedOnStyles = Vale, Microsoft

# Right rule, 9,881 hits in legacy pages. Advisory until the backlog is worked down.
Microsoft.Wordiness = suggestion

# House style uses no contractions in reference docs.
Microsoft.Contractions = NO
```

The value is `NO` to switch a rule off, or a level — `suggestion`, `warning`,
`error` — to change it. Write the reason as a comment every time; an
unexplained `NO` is indistinguishable from someone silencing a rule to get a
build through.

**7. Re-run the count from step 1** and confirm each change took effect. A rule
that still reports at its old level is in the wrong section or misspelled —
Vale does not warn about an override that matches nothing.

**8. Report, before and after.**

```
Vale triage
===========
Before: 18,412   errors 3 · warnings 11,085 · suggestions 7,324
After:  14,970   errors 3 · warnings  1,204 · suggestions 13,763
Blocking today: 3 alerts across 2 rules

Top rules
  9,881  warning     Microsoft.Wordiness      → downgraded to suggestion (real backlog, right rule)
  3,442  suggestion  Microsoft.Contractions   → disabled (house style differs)
  1,204  warning     Microsoft.Headings       → fix (mechanical, 40 files)

Written to .vale.ini: 2 overrides, each with its reason
Unchanged: 31 other rules, 3,885 alerts
```

## Do not

- Do not propose raising `MinAlertLevel` as the fix. It hides alerts without
  deciding anything, and the decisions are the point.
- Do not disable a rule because it is noisy on legacy content that new content
  would pass. Downgrade it.
- Do not recommend a bucket without saying what it costs.
- Do not write to `.vale.ini` before the user has agreed to the plan, and do
  not add an override without a comment giving the reason.
- Do not edit anything under `StylesPath` to change a rule's level. The
  override belongs in `.vale.ini`; `vale sync` overwrites the rest.
