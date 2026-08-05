#!/bin/sh
#
# PostToolUse: lint the prose file that was just written and hand any
# error-level alerts straight back to Claude.
#
# Silent by design. A repository that hasn't adopted Vale, a machine without
# the binary, a file Vale doesn't lint, or a clean run all exit 0 with no
# output — installing this plugin must not add noise to unrelated work.
#
# Error level only. Warnings and suggestions are advisory by the project's own
# choice, and surfacing them on every edit is how people turn a linter off.
# POSIX sh, not bash: the only bashism was `set -o pipefail`, which dash rejects
# outright and which nothing here needs — the one pipeline feeds a variable that
# is checked for emptiness two lines later. Staying POSIX means the hook runs
# under whatever /bin/sh a machine has, including minimal containers.
set -u

# jq parses the hook payload and Vale's JSON; the `fix` skill already needs it.
for bin in vale jq; do
	command -v "$bin" >/dev/null 2>&1 || exit 0
done

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
[ -n "$file" ] && [ -f "$file" ] || exit 0

case "$file" in
*.md | *.mdx | *.markdown | *.adoc | *.rst | *.org | *.txt) ;;
*) exit 0 ;;
esac

# No resolvable config means this repository hasn't adopted Vale. Nothing to say.
vale ls-config >/dev/null 2>&1 || exit 0

# --no-exit because error-level alerts are the case we want to report, and
# without it Vale's nonzero exit would look like a failed run.
alerts=$(vale --no-exit --output=JSON "$file" 2>/dev/null) || exit 0

summary=$(printf '%s' "$alerts" | jq -r '
  [ .[][]? | select(.Severity == "error") ]
  | if length == 0 then empty
    else "Vale reports \(length) error-level alert(s) in this file:\n"
       + ([ .[] | "  line \(.Line): \(.Check) — \(.Message)" ] | join("\n"))
       + "\n\nFix these before moving on, preserving the markup exactly. Do not disable a rule to clear one."
    end
')

[ -n "$summary" ] || exit 0

jq -n --arg ctx "$summary" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
