---
name: onboard
description: Take a repository from no Vale to a quiet, committed baseline in one pass — config, vocabulary, a decision per noisy rule, and CI. Use when the user says "set up vale end to end", "onboard this repo to vale", "get us started with prose linting", or asks for setup and wants it finished rather than started.
---

# Onboard a repository to Vale

## When to use this

The repository has no working Vale config and the user wants the whole job:
not a `.vale.ini` and two thousand alerts, but a baseline the team can keep.

This skill is the order of operations. The work in each step belongs to
`setup`, `vocab`, `triage` and `ci`; follow those, and their "Do not" lists
still apply. If the user wants only one of them, use that one instead.

## Ask once, up front

Everything that is the team's decision, in one message, before any file
changes. Offer a default for each so a bare "go" is a usable answer:

1. **Where the prose lives** — say what you found (`docs/`, 42 `.md`, 16
   `.mdx`) and ask them to confirm.
2. **Which style package** — Microsoft, Google, or another from
   <https://vale.sh/explorer>. It is an editorial choice.
3. **Whether CI should block**, and on which runner. Default: advisory.
4. **Whether to fix what is left** at the end, or stop at the baseline.
   Default: stop.

Do not ask again mid-run unless a step turns up something these answers do not
cover.

## Workflow

**1. Set up** (`setup`). Config, ignore rules, `vale sync`, one file linted.
If `vale ls-config` finds a config that does not resolve, repair that one
rather than writing a second.

**2. Take the first count** and keep it — it is the "before" in the report:

```bash
vale --no-exit --output=JSON <path> > /tmp/vale-before.json
```

**3. Vocabulary before triage** (`vocab`). `Vale.Spelling` is an error-level
rule and on a first run it is commonly the largest source of errors, nearly
all of them product names. Triaging before the vocabulary exists means
deciding about noise that is about to disappear. Read the list; what is left
after the vocabulary should be real typos.

**4. Triage** (`triage`). A package ships some of its rules at `error`, so a
first run usually has errors nobody chose. Each one needs a decision before CI
can block on anything. Show the plan with the exact lines, get a yes, write
them with their reasons, re-run.

**5. Confirm what blocks.**

```bash
vale --output=line <path> >/dev/null; echo "exit $?"
```

Exit 1 means errors remain. That is a fine place to stop — they are the short
list of things worth fixing — but say it, because it decides step 6.

**6. CI** (`ci`). If errors remain and the user asked for a blocking job,
either fix them first (`fix`) or wire it advisory and say why. Do not ship a
job that is red on its first run. If the repository already runs Vale in CI,
update that job rather than adding a second.

**7. Commit** the config, the ignore rules, the vocabulary and the CI change
together, following the repository's conventions. Not the synced packages.

**8. Report.**

```
Vale onboarding
===============
Config:      .vale.ini  ([*.{md,mdx}] → Vale, Microsoft)
Vocabulary:  ValeDocs, 12 terms accepted
Baseline:    4 overrides written, each with its reason

              total   errors  warnings  suggestions
First run       404       52        99          253
After vocab     382       30        99          253
After triage    335       11        65          259

Blocking now: 11 alerts, 1 rule (Vale.Spelling — real typos, listed below)
CI:           GitHub Actions, advisory
Left for you: fix the 11, then the job can block
```

## Do not

- Do not skip the questions and pick the style package or the CI mode
  yourself. A baseline built on a guess gets thrown away.
- Do not reach a clean exit by raising `MinAlertLevel`, adding `--no-exit`, or
  accepting typos into the vocabulary. The count that matters is the one
  nobody had to hide.
- Do not edit prose during onboarding unless the user asked for the fix step.
  A setup pull request that also rewrites forty pages will not be reviewed.
- Do not report "set up" without the before and after counts and the exit
  code.
