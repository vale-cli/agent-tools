---
name: onboard
description: Take a repository from no Vale to a quiet, committed baseline in one pass — config, vocabulary, a decision per noisy rule, and CI — with one proposal and one yes. Use when the user says "set up vale end to end", "onboard this repo to vale", "get us started with prose linting", or asks for setup and wants it finished rather than started.
---

# Onboard a repository to Vale

## When to use this

The repository has no working Vale config and the user wants the whole job:
not a `.vale.ini` and two thousand alerts, but a baseline the team can keep.

The details of each part belong to `setup`, `vocab`, `triage` and `ci`, and
their "Do not" lists still apply. This skill is how to do all four without
stopping four times. If the user wants only one of them, use that one.

## The shape: look, draft, one yes, apply

Everything up to the proposal happens in a temp directory. Nothing in the
repository changes until the user has seen the whole baseline — the config,
the vocabulary, each override and its reason, the CI job, and the numbers —
and said yes once.

That is what makes it feel finished rather than interrogated: the user is
asked to approve a concrete result, not to answer questions about a tool they
have not seen run yet.

Say one short line as each step starts ("Trying Microsoft and Google against
docs/…"). Long silences read as being stuck.

## Workflow

**1. Look.** No questions yet.

- `vale --version`. If it fails, install it (see `setup`) and say that you did.
- `vale ls-config`. If a config already resolves, this is not onboarding — say
  so and offer `triage`. If one exists and fails to load, repair it rather
  than writing a second.
- Find the prose: `docs/`, `content/`, `website/docs/`, root `*.md`. Leave out
  vendored, generated and changelog files.
- Note what is already there: an existing CI workflow, a pre-commit config, a
  written style guide.

**2. Preview the candidates.** `scripts/preview.sh`, beside this file, builds
a throwaway config in a temp directory and prints the counts by severity and
rule plus the terms spell check does not know. It needs only `vale`, and it
writes nothing to the repository:

```bash
sh <this skill's directory>/scripts/preview.sh -p Microsoft <path>
sh <this skill's directory>/scripts/preview.sh -p Google <path>
```

If the user named a package, preview that one. Otherwise preview Microsoft and
Google, so the choice between them comes with numbers instead of a shrug.

**3. Draft the baseline, still in temp files.**

- *Vocabulary first.* `Vale.Spelling` is error-level and usually the largest
  source of first-run errors, nearly all of them names. Put the real terms in
  a scratch `accept.txt`. Leave out anything that looks like a typo or an
  inconsistent casing — those are findings, and they belong in the report.
- *Then overrides*, by the `triage` buckets, in a scratch file with the reason
  as a comment above each line. A package ships some rules at `error`; each of
  those needs a decision before CI can block on anything.
- *Run the preview again* with both, and keep the output:

```bash
sh <this skill's directory>/scripts/preview.sh -p Microsoft -a accept.txt -o overrides.ini <path>
```

**4. Propose once.** One message, in this order, short enough to read:

```
Vale baseline for docs/ (40 .md, 14 .mdx) — nothing written yet

              total   errors  warnings  suggestions
First run       404       52        99          253
With baseline   335       11        65          259

Package:     Microsoft   (Google: 571 alerts, 67 errors — say so to switch)
Vocabulary:  12 terms    Jilles, Tengo, Linode, Buildkite, …
Overrides:   4
  Microsoft.We = NO                    docs address the reader as "we"
  Microsoft.Quotes = warning           right rule, 9 existing hits
  Microsoft.Contractions = suggestion  register varies by page
  Microsoft.Foreign = warning          right rule, 4 existing hits
CI:          update .github/workflows/main.yml, advisory
Still errors: 11 — inconsistent spellings ("VSCode", "intellij"). Real
              findings; I'd leave them for a follow-up fix.

Apply this? Or tell me what to change.
```

Every editorial choice is in there with the default you picked and the
alternative: the package, each override, whether CI blocks. A "yes" accepts
all of it; "use Google" or "keep We" changes one line and you re-preview —
do not start over, and do not re-ask what was already accepted.

Default CI to advisory. A job that is red on its first run teaches the team to
ignore it.

**5. Apply**, in one go, once they say yes:

- `.vale.ini`, the ignore rules and `vale sync` (`setup`)
- the vocabulary, named in the config (`vocab`)
- the overrides, each with its reason (`triage`)
- the CI change — update a job that already runs Vale rather than adding a
  second (`ci`)

**6. Verify against the preview.**

```bash
vale --output=line <path> >/dev/null; echo "exit $?"
```

The real run should match the previewed numbers. If it does not, a section
glob or an override is not matching; find out which before reporting.

**7. Commit** the config, ignore rules, vocabulary and CI change together,
following the repository's conventions. Not the synced packages.

**8. Close with the result and one next step.** The table from the proposal,
what was committed, the exit code, and the single most useful thing to do
next — usually "fix the 11 remaining errors, then CI can block". Not a menu.

## If it is interrupted

Running this again should pick up, not restart. Check what exists — a config
that resolves, a vocabulary, overrides with comments, a CI job — and do only
what is missing, saying what you skipped.

## Do not

- Do not write to the repository before the yes. The preview exists so that
  nothing has to be undone.
- Do not ask questions the preview can answer. "Which package?" with no
  numbers is a worse question than the proposal.
- Do not reach a clean exit by raising `MinAlertLevel`, adding `--no-exit`, or
  accepting typos into the vocabulary. The count that matters is the one
  nobody had to hide.
- Do not edit prose during onboarding unless the user asked for it. A setup
  pull request that also rewrites forty pages will not be reviewed.
- Do not bury the proposal in explanation. If it does not fit on one screen,
  cut the commentary, not the overrides.
