#!/bin/sh
#
# PostToolUse: lint the prose file that was just written and hand the alerts
# straight back to Claude.
#
# Silent by design. A repository that hasn't adopted Vale, a machine without
# the binary, a file Vale doesn't lint, or a clean run all exit 0 with no
# output — installing this plugin must not add noise to unrelated work.
#
# Errors only by default. Warnings and suggestions are advisory by the
# project's own choice, and surfacing them on every edit is how people turn a
# linter off. Widen it for a style whose rules are deliberately advisory, where
# the default would leave the hook silent.
#
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

# Severities are ordered suggestion < warning < error, and the threshold names
# the lowest one that reaches Claude.
#
# The plugin's `level` option arrives as CLAUDE_PLUGIN_OPTION_LEVEL and is the
# normal way to set this; VALE_HOOK_LEVEL wins over it, for anyone running this
# script outside the plugin or overriding it for one session. The option always
# carries its default, so without the override it is never unset.
#
# userConfig has no enum type, so the value is free text and is validated here:
# anything unrecognised falls back rather than failing, because a typo in
# someone's settings should not turn the hook into an error on every edit.
level=${VALE_HOOK_LEVEL:-${CLAUDE_PLUGIN_OPTION_LEVEL:-error}}
case "$level" in
warning) keep='["error","warning"]' ;;
suggestion) keep='["error","warning","suggestion"]' ;;
*)
	level=error
	keep='["error"]'
	;;
esac

# No resolvable config means this repository hasn't adopted Vale. Nothing to say.
vale ls-config >/dev/null 2>&1 || exit 0

# --no-exit because error-level alerts are the case we want to report, and
# without it Vale's nonzero exit would look like a failed run.
alerts=$(vale --no-exit --output=JSON "$file" 2>/dev/null) || exit 0

# Vale's own MinAlertLevel gates what appears in the JSON at all; this is the
# second gate, over whatever survived the first.
summary=$(printf '%s' "$alerts" | jq -r --argjson keep "$keep" --arg level "$level" '
  [ .[][]? | select(.Severity as $s | $keep | index($s)) ]
  | if length == 0 then empty
    else "Vale reports \(length) alert(s) at \($level) level or above in this file:\n"
       + ([ .[] | "  line \(.Line): \(.Check) [\(.Severity)] — \(.Message)" ] | join("\n"))
       + "\n\n"
       + (if $level == "error"
          then "Fix these before moving on, preserving the markup exactly."
          else "Fix the errors before moving on, preserving the markup exactly; treat the rest as advice."
          end)
       + " Do not disable a rule to clear one."
    end
')

[ -n "$summary" ] || exit 0

jq -n --arg ctx "$summary" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
