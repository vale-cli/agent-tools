---
name: onboard
description: Take a repository from no Vale to a quiet, committed baseline in one pass — config, vocabulary, a decision per noisy rule, and CI — with one proposal and one yes. Use when the user says "set up vale end to end", "onboard this repo to vale", "get us started with prose linting", or asks for setup and wants it finished rather than started.
allowed-tools: Bash(sh ${CLAUDE_SKILL_DIR}/scripts/preview.sh *), Bash(sh ${CLAUDE_SKILL_DIR}/scripts/survey.sh *)
---

# Onboard a repository to Vale

## When to use this

The repository has no working Vale config and the user wants the whole job:
not a `.vale.ini` and two thousand alerts, but a baseline the team can keep.

The details of each part belong to `setup`, `vocab`, `triage`, `tune` and
`ci`. This skill is how to do all of them without stopping five times. If the
user wants only one, use that one.

**Where this skill and the others disagree, this one wins.** They each say to
ask before choosing — the package, the overrides, whether CI blocks, the
reason for a style choice. Here the single proposal in step 4 is that
question, asked once with the answer you would give. Their report formats are
likewise replaced by the one at the end. Their "Do not" lists still apply.

`${CLAUDE_SKILL_DIR}` in the commands below is the directory this file is in.
If it reaches you as literal text, use that directory's path instead.

## The shape: look, draft, one yes, apply

Everything up to the proposal happens in a temp directory. Nothing in the
repository changes until the user has seen the whole baseline — what it found,
the config, the vocabulary, each choice and its reason, the CI job, and the
numbers — and said yes once.

That is what makes it feel finished rather than interrogated: the user is
asked to approve a concrete result, not to answer questions about a tool they
have not seen run yet.

Say one short line as each step starts ("Trying Microsoft and Google against
docs/…"). Long silences read as being stuck.

**Speed is part of the result.** The proposal should be on screen within a
couple of minutes of the request: the preview script takes seconds, and the
drafting is a handful of decisions, not a study. Do not read every file or
every alert before proposing. If something would take long — a huge corpus, a
package that will not sync — say so and propose on a sample.

## Workflow: look

**1. Look.** No questions yet. `scripts/survey.sh` reads the repository in a
fraction of a second and prints what there is to work with: where the prose
is, translated docs, source code by language, a written style guide, existing
CI and hook runners, and whether Vale is installed or configured.

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/survey.sh
```

It reports facts, not decisions. Then:

- `vale --version`. If it fails, install it — `setup` has the script — and
  say that you did. Do not stop to ask.
- `vale ls-config`. If a config already resolves, this is not onboarding — say
  so and offer `triage`. If one exists and fails to load, repair it rather
  than writing a second.
- Find the prose. If a CI job or script already lints a path, that path is the
  team's answer — use it, and mention anything in it that looks like
  boilerplate. Otherwise: `docs/`, `content/`, `website/docs/`, root `*.md`.
  Give Vale the docs directory, never the repository root: it does not skip
  `node_modules` or vendored trees on its own.
- Translated docs inside the path you are about to lint must not be read as
  English: that is hundreds of false alerts. The quiet default is a section
  that names the language and leaves spell check off —
  `[docs/fr/**/*.md]` with `Lang = fr`, `BasedOnStyles = Vale` and
  `Vale.Spelling = NO`. Spell-checking them needs a dictionary, an option below.
## Workflow: what is already there

- Note what is already there: a CI workflow, a pre-commit config, a written
  style guide, and leftovers from an older Vale setup such as a script that
  downloads styles by hand. Leftovers go in the report, not in the bin.
- Carry over decisions the project made in another tool. A word list is
  imported into the vocabulary (step 3). A config for markdownlint, textlint,
  codespell or commitlint is evidence of what the team cares about: read it,
  and let it inform the style choices and the options list. Do not remove or
  replace the other tool; say that Vale now overlaps with it and leave the
  choice to them.
- Pick the project's name, used for the vocabulary and any own rules: the
  product or repository name in one capitalised word. Not `Vale`, and not a
  package's name; where that leaves nothing, `Docs`.

## Workflow: preview

**2. Preview the candidates.** `scripts/preview.sh` builds a throwaway config
in a temp directory. It needs only `vale` and writes nothing to the
repository:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/preview.sh -p Microsoft -p Google <path>
sh ${CLAUDE_SKILL_DIR}/scripts/preview.sh -p Microsoft <path>
```

The first form is a side-by-side count. The second is one package in full:
counts by severity and rule, a real alert from the user's own files for every
error-level rule and the busiest of the rest, and each term spell check does
not know with where it first appears. If the user named a package, go straight
to the second. Otherwise compare Microsoft and Google and take the quieter one
as the default.

For translated docs or source code, the same script previews those too —
`-l fr <path>` for a language, `-k <path>` for comments — with Vale's built-in
rules alone, since the style packages are written for English prose.

## Workflow: draft

**3. Draft the baseline, still in temp files.** Five things, a minute or two each.

- *Front matter.* Look at where the unknown terms are. Hits on the first lines
  of files are front matter — `id: vscode`, a `slug` — and those are URLs, not
  prose. Do not accept them and never "fix" them. Leave unlinted the fields
  that actually produced hits, such as `-i text.frontmatter.id`; `vocab` has the config
  line this becomes.
- *Which English.* `vocab`'s `scripts/dictionary.sh -d <path>` counts
  American and British spellings in a second. Keep the result for the options
  list. Do not install a regional dictionary during onboarding: it multiplies
  unknown terms.
- *Vocabulary.* `Vale.Spelling` is error-level and usually the largest source
  of first-run errors, nearly all of them names. If the survey found a word
  list kept for another spell checker, start from it: `vocab`'s
  `scripts/import-words.sh` turns it into entries, keeping only the words
  Vale does not already know. Then put the remaining real terms from the
  preview in the same scratch `accept.txt`. Leave out anything that looks like a typo or an
  inconsistent casing — those are findings.
## Workflow: decide the rules

- *Overrides.* Every error-level rule needs a decision before CI can block on
  anything; the preview's examples show one real hit of each. Use the `triage`
  buckets, in a scratch file, with the reason as a comment above each line.
  There is nobody to ask for reasons yet, so write what the corpus shows
  ("52 uses across the tutorials").
- *Style choices and preferred terms.* The table in `tune` names the choices
  teams argue about. Take what the docs already do as the default, read from
  the rule's count: few hits means the docs follow the rule, many means they
  do not. An inconsistent spelling in the unknown-terms list (`VSCode` beside
  "VS Code") is a pair for `tune`'s `Terms.yml` template, in a scratch style
  directory. If a heading rule is flagging product names, accept the names;
  do not switch the rule off.

Then run the preview once more with all of it, and keep the output:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/preview.sh -p Microsoft -a accept.txt -o overrides.ini \
  -i text.frontmatter.id -s <scratch>/<Project> <path>
```

## Workflow: propose

**4. Propose once.** One message, in this order:

```
Vale baseline for docs/ (40 .md, 14 .mdx) — nothing written yet

              total   errors  warnings  suggestions
First run       404       52        99          253
With baseline   335        5        65          265

What it found, in your files
  "VSCode" in creating-plugin.md:16 — elsewhere you write "VS Code"
  "e.g.," in options/core.md:19 → "for example"
  "Intellij" in clients/intellij.md:10 — the product is "IntelliJ"

Package:     Microsoft   (Google: 571 alerts, 67 errors — say so to switch)
Path:        docs/       the path your CI job already lints
Vocabulary:  41 terms    29 carried over from cspell.json, 12 new: Jilles, Tengo, …
Not linted:  front matter `id` and `slug` — page URLs, not prose

Style choices — from how the docs are written today; change any
  Headings       sentence case   12 hits, 8 of them product names I've accepted
  "We"           allowed         52 uses; the docs speak as "we" throughout
  Contractions   advice only     8 hits; was blocking
  "e.g."         spell out       4 hits; shown in review, not blocking
  Terms          VS Code, IntelliJ   5 inconsistent spellings get a fix

Other overrides: 1
  Microsoft.Quotes = warning     9 hits, right rule; not blocking yet
Where it runs — change any
  GitHub Action  update .github/workflows/main.yml — advisory, and only on
                 lines a pull request adds, so the backlog lands on nobody.
                 Changes: action v1 → v3, trigger gains pull_request.
  pre-commit     add Vale to .pre-commit-config.yaml — errors only
Still errors: 5 — the inconsistent spellings above. Real findings; I'd leave
              them for a follow-up fix.

Not included — say the word for any of these
  Blocking checks    5 errors would fail them today; fix those first
  One-click fixes    suggested changes on pull requests (not from forks)
  French docs        docs/fr (38 files) are skipped; needs a dictionary
  Code comments      212 .go, 40 .py files
  One spelling       79 American, 1 British ("centre") — enforce American
  Commit messages    closest to the "seven rules": 10 of your last 14 pass
  Your style guide   docs/style-guide.md → tested rules
  A written guide    generated from this config, for contributors
  In your editor     alerts as you type

The reasons in the config are what I observed, for you to replace with yours.
Apply this as a pull request? Or tell me what to change.
```

## Proposal: what to say

Lead with two or three things it actually caught, picked from the preview's
examples — a real inconsistency in a named file convinces where a count does
not. Choose findings the team would agree are mistakes, not the busiest rule.
Shorten long paths to the file name.

Say in the proposal, not afterwards, what you will change in a file the team
already owns: the CI workflow's action, trigger and options. If the path you
lint is not the obvious one, give it a `Path:` line with the reason.

A style-choice line earns its place with a decision or with evidence. Where
you are leaving a rule as shipped and have nothing to say about it, leave the
line out. Counts measured in different ways can differ by one or two;
report each as measured.

Use only evidence the preview gave you: rule counts, examples, term
locations. A hit count is enough to justify a
default.

Every editorial choice is in there with the default you picked: the package,
the style choices in plain words, each remaining override, whether CI blocks.
Name choices the way the team would — "title case", not `capitalization` — and
keep rule names for lines with no plainer description. A "yes" accepts all of
it; "use Google" or "keep We" changes one line and you re-preview. Do not
start over, and do not re-ask what was already accepted.

## Proposal: where it runs

**Where it runs is part of the baseline, not an afterthought.** A config that
only runs when someone remembers to type `vale` is not adopted. `ci`'s
`scripts/ci.sh detect` says what the repository has; propose from that:

- *A GitHub repository:* the action, on by default. Update a workflow that
  already runs Vale; otherwise add `.github/workflows/vale.yml`.
- *A repository that already uses pre-commit:* the Vale entry, on by default.
- *No pre-commit here:* list it under "Not included" — "pre-commit hook:
  stops a commit with errors; each contributor installs it once" — and do not
  introduce it unasked.
- *Not on GitHub:* say so, leave the action out, and offer the generic runner
  command from `ci` under "Not included".

Generate the files with `ci.sh action` and `ci.sh pre-commit` at the apply
step; do not write the YAML from memory.

Default CI to advisory. A job that is red on its first run teaches the team to
ignore it.

## Proposal: quiet by default

**Quiet by default, complete by mention.** The baseline you propose is the
smallest one that is useful: English prose, one package, advisory CI. Every
other thing Vale can do for this repository goes in "Not included" — named,
with one fact, and switched off. The rules for that list:

- One line each, and only options the survey shows apply here. No source
  files, no code-comments line. No style guide found, no style-guide line.
- One fact per line, from something you already ran: the survey, the preview,
  `dictionary.sh -d`. For commit messages, `commits`' `scripts/history.sh
  -n 20` takes a few seconds; skip the line if it is not available, or if the
  repository has fewer than ten commits to judge by.
- No explanation and no recommendation. If they ask about one, explain then.
- Never turn one on because it seems like a good idea. Each is a separate
  yes, and each has its own skill: `ci` for blocking, suggested fixes and a
  pre-commit hook,
  `setup` for translations and code comments, `vocab` for dictionaries,
  `commits`, `from-guide`, `write-guide`.
- Leave a line out once it is done. A repository that already has a hook
  runner linting commits does not need the offer.

If what is left includes errors you cannot clear honestly — a false positive
with no clean exemption — say so in "Still errors" and keep CI advisory.
That is a better proposal than a clean number.

## Workflow: apply and verify

**5. Apply**, in one go, once they say yes:

- `.vale.ini`, the ignore rules and `vale sync` (`setup`)
- the vocabulary and any `IgnoredScopes` line, above the first `[section]`
  (`vocab`)
- the overrides, each with its reason (`triage`)
- the style choices and any own rules, with
  `vale test --coverage styles/<Project>` passing (`tune`)
- where it runs — the workflow and, if chosen, the pre-commit entry, from
  `ci`'s `scripts/ci.sh`. Update a job that already runs Vale rather than
  adding a second, and say what you changed about its trigger (`ci`)

**6. Verify against the preview.** The same script, pointed at the real
config, prints the same report:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/preview.sh -r <path>
```

The whole report should equal the last preview's, examples included: the
script sorts what it reads, so the two can be compared line for line. If they do not, a section glob,
an override or the ignored scopes is not matching; find out which before
reporting. Then the exit code, which is what CI sees:

```bash
vale --output=line <path> >/dev/null; echo "exit $?"
```

Exit 1 is expected while errors remain.
Exit 0 means a blocking job would pass today.

## Workflow: commit

**7. Commit, and open it as a pull request where the team reviews that way.**
The config, ignore rules, vocabulary, own rules and CI change go in one
commit on a branch, following the repository's conventions. Not the synced
packages.

A baseline is a set of editorial decisions, and the person at the keyboard is
rarely the only one they affect. So the default ending is a pull request
whose description is the proposal — the table, what it found, each choice and
its reason, the "Not included" list — so the rest of the team approves the
same thing the user did, and nothing reaches the main branch until they do.
Add one line at the top saying how to try it locally (`vale sync`, then
`vale <path>`).

Follow what the user and the repository want, in this order: what the user
said ("just commit it", "no PR"); the repository's own rules about branches
and pull requests; then this default. If you cannot open one — no remote, no
access — commit on a branch, say so, and put the description in the final
message for them to paste.

## Workflow: finish

**8. Close with the result and one next step.** The table from the proposal,
what was committed, the exit code, any leftovers you noticed, and the single
most useful thing to do next — usually "fix the 5 remaining errors, then CI
can block". Not a menu: the options were in the
proposal. If they picked one — the editor, say — do it or point to it
now (<https://docs.vale.sh/guides/lsp.md> for the language server).

## If the proposal comes from the setup pane

The `vale-onboard` plugin draws this proposal as a pane: the person picks the
package, what each rule does and which words to accept there, and presses
Apply, which puts the result in the prompt as a message beginning "Apply this
Vale baseline". That message is the yes. Do not re-preview the candidates or
re-propose; go to the apply step with exactly what it lists.

- Write each override it names, with the reason it gives as the comment.
- Accept only the words it lists. The ones it says were left unticked are
  findings: mention them at the end, do not add them.
- Its "Expected after applying" counts are what step 6 should match.
- "Where it runs" names the checks to add and whether they block. Add
  exactly those with `ci`'s `scripts/ci.sh`; where it says nowhere, add none.
- Anything under "Also set up" is a yes to that option; use its skill after
  the baseline is committed.

## If it is interrupted

Running this again should pick up, not restart. Check what exists — a config
that resolves, a vocabulary, overrides with comments, a CI job — and do only
what is missing, saying what you skipped.

## Do not

- Do not write to the repository before the yes. The preview exists so that
  nothing has to be undone.
- Do not push to the default branch or merge the pull request yourself. The
  yes was to the baseline, not to skipping the team's review.
- Do not ask questions the preview can answer. "Which package?" with no
  numbers is a worse question than the proposal.
- Do not reach a clean exit by raising `MinAlertLevel`, adding `--no-exit`, or
  accepting typos into the vocabulary. The count that matters is the one
  nobody had to hide.
- Do not edit prose during onboarding unless the user asked for it. A setup
  pull request that also rewrites forty pages will not be reviewed.
- Do not change a front matter `id` or `slug` to satisfy spell check. It is a
  URL.
- Do not bury the proposal in explanation. Cut commentary before cutting a
  choice — but an error you cannot clear is a choice, not commentary.
