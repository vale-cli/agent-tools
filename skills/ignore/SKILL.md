---
name: ignore
description: Stop Vale from flagging text that is not prose — shortcodes, templating tags, generated blocks, one quoted passage — without switching a rule off. Use when the user says "vale is flagging our shortcodes", "ignore this block", "false positive", or "stop linting the generated pages".
---

# Exclude what is not prose

## When to use this

A rule is right in general and wrong about a specific piece of text: a
templating tag, an include directive, a quotation, a generated file. The fix
is to take that text out of Vale's view, at the narrowest scope that works.

If the rule is wrong for the project's own writing, that is a decision about
the rule. Use `triage` or `tune`. If the text is a correctly spelled term, or a
front matter field such as `id` or `slug`, use `vocab`.

## Prerequisites

1. `vale ls-config` resolves.
2. You have the alerts in hand, and have read the flagged text. Collect them
   rather than working from a description:

```bash
vale --output=line <path>
```

## Pick the narrowest tool

Work down this list and stop at the first that fits.

| what is being flagged | tool | where |
|---|---|---|
| a whole directory or file kind | a narrower path or section glob | the `vale` invocation, `.vale.ini` |
| a recurring inline token, like `{{ var }}` | `TokenIgnores` | `.vale.ini` |
| a recurring block, like a shortcode pair | `BlockIgnores` | `.vale.ini` |
| the contents of an HTML tag | `IgnoredScopes` (inline), `SkippedScopes` (block) | `.vale.ini` |
| one passage, once | a comment in the file | the file |

A pattern in the config fixes every file at once and stays fixed for the next
writer. A comment fixes one place and has to be repeated, so it is last.

## Workflow

**1. Group the alerts by what the flagged text is**, not by rule. Forty alerts
from six rules on `{{< note >}}` blocks are one problem.

**2. For a recurring token or block, write the pattern** in the section that
covers those files. The first capture group is what Vale ignores:

```ini
[*.md]
BasedOnStyles = Vale, Microsoft

TokenIgnores = (\{\{[^}]+\}\})
BlockIgnores = (?s) *(\{\{< note >\}\}.*?\{\{< /note >\}\})
```

Several patterns are separated by commas, so a comma inside one is written
`\,`. Both keys need a markup format; they do nothing in a source file.

**3. For an HTML tag**, name it. Setting either key replaces its default list,
so keep the defaults:

```ini
IgnoredScopes = code, tt, kbd, samp, abbr
SkippedScopes = script, style, pre, figure, noscript, iframe, details
```

**4. For one passage**, use the comment form the file's format reads. In
Markdown:

```markdown
<!-- vale Microsoft.Passive = NO -->
The quoted sentence that must stay as written.
<!-- vale Microsoft.Passive = YES -->
```

Name the rule. `<!-- vale off -->` switches off every rule, including the
ones that would have caught a real mistake in the same passage. MDX, AsciiDoc,
reStructuredText, and Org each have their own form, listed per format under
<https://docs.vale.sh/formats/markdown.md> and its siblings.

**5. Re-run and compare.** The alerts you targeted should be gone and the
total should have dropped by that number, no more. A pattern that removed
extra alerts is ignoring prose.

**6. Report.**

```
Vale ignore
===========
Shortcodes ({{< note >}}):  BlockIgnores in [*.md]      -212 alerts
Template vars ({{ x }}):    TokenIgnores in [*.md]       -64 alerts
Changelog quote:            comment, docs/history.md      -1 alert
Before 1,940 → after 1,663. No other alerts changed.
```

## Do not

- **Do not switch a rule off to remove a false positive.** That removes its
  true positives too, in every file.
- **Do not use `<!-- vale off -->` where a named rule will do**, and never
  leave one without its matching `on`.
- **Do not write a pattern broader than the text it is for.** `(\{.*\})` on a
  line with two tags ignores the sentence between them.
- **Do not ignore a passage because fixing it is tedious.** This skill is for
  text that is not prose, or must not change.
