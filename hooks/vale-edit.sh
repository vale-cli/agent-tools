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
# POSIX sh and POSIX tools only. This is the always-on component, so it
# depends on nothing optional: Vale renders alerts through the template
# shipped beside this script, sed pulls the file path out of the payload, and
# awk does the filtering and the JSON escaping. The `fix` skill still uses
# jq, where a missing binary fails visibly instead of silently.
set -u

command -v vale >/dev/null 2>&1 || exit 0

payload=$(cat)

# The one field this hook needs from the payload. The pattern stops at a
# quote, so a name containing one -- which JSON must escape -- doesn't
# match and the edit is skipped: pathological names are lost, never
# mangled. A Windows path arrives with doubled backslashes; they become
# forward slashes, which Git Bash and Vale both accept, and which is the
# normalization the hooks documentation itself shows.
file=$(printf '%s\n' "$payload" |
	sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
	head -n 1 |
	sed 's/\\\\/\//g; s/\\\//\//g')
case "$file" in
*\\*) exit 0 ;;
esac
[ -n "$file" ] && [ -f "$file" ] || exit 0

# Prose formats, and the source languages whose comments Vale reads. A
# source file is only ever linted if the project's configuration has a
# section matching it; otherwise Vale reports nothing and the hook stays
# silent, so listing them here costs a repository without one nothing.
case "$file" in
*.md | *.mdx | *.markdown | *.adoc | *.rst | *.org | *.txt) ;;
*.go | *.py | *.js | *.jsx | *.mjs | *.cjs | *.ts | *.tsx | *.mts | *.cts) ;;
*.java | *.kt | *.kts | *.rs | *.rb | *.c | *.h | *.cpp | *.cc | *.hpp | *.cs) ;;
*.swift | *.scala | *.php | *.lua | *.ex | *.exs | *.hs | *.jl | *.proto) ;;
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
# The plugin offers the three values as a fixed list, but VALE_HOOK_LEVEL is
# free text and older settings may hold anything, so the value is still
# validated here: anything unrecognised falls back rather than failing, because
# a typo should not turn the hook into an error on every edit.
level=${VALE_HOOK_LEVEL:-${CLAUDE_PLUGIN_OPTION_LEVEL:-error}}
case "$level" in
warning) keep='^(error|warning)$' ;;
suggestion) keep='^(error|warning|suggestion)$' ;;
*)
	level=error
	keep='^error$'
	;;
esac

# Anchor at the file's own configuration, not the session's working
# directory. The hook receives an absolute path and may run from anywhere:
# linted as-is, a path-scoped section like `[docs/**/*.md]` never matches,
# and Vale resolves whichever .vale.ini the *session* sits under -- both
# quietly, as a clean pass. Walking up from the file finds the config the
# file actually belongs to; Vale then runs from there, on the path relative
# to there, which is the form path-scoped sections are written against.
# The walk stops when dirname stops making progress rather than at "/",
# because not every tree tops out there: a Windows drive root under Git
# Bash is its own fixed point.
root=$(dirname "$file")
adopted=1
prev=''
while [ "$root" != "$prev" ] && [ ! -f "$root/.vale.ini" ] && [ ! -f "$root/_vale.ini" ]; do
	prev=$root
	root=$(dirname "$root")
done
if [ ! -f "$root/.vale.ini" ] && [ ! -f "$root/_vale.ini" ]; then
	adopted=0
	root=$(dirname "$file")
fi
rel=${file#"$root"/}

# No config above the file and none resolvable from its directory means this
# repository hasn't adopted Vale: nothing to say. A config the walk *did*
# find counts as adoption even when it fails to load -- `ls-config` exits
# nonzero for both, and a broken config deserves the report below, not the
# silence of a repository that never opted in.
if [ "$adopted" -eq 0 ]; then
	(cd "$root" && vale ls-config >/dev/null 2>&1) || exit 0
fi

# emit wraps a message in the hook's JSON envelope, escaping it with awk:
# backslashes first, then quotes and tabs, and real newlines become \n as the
# lines are joined. Alert messages quote the text they matched, so every one
# of these appears in practice.
emit() {
	printf '%s' "$1" | awk '
		BEGIN { printf "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"" }
		{
			gsub(/\\/, "\\\\")
			gsub(/"/, "\\\"")
			gsub(/\t/, "\\t")
			gsub(/\r/, "")
			printf "%s%s", (NR > 1 ? "\\n" : ""), $0
		}
		END { print "\"}}" }
	'
}

# The template renders one alert per line -- severity, line, check, message,
# tab-separated -- so the parsing below and the format are shipped together.
tmpl=$(dirname "$0")/vale-hook.tmpl
[ -f "$tmpl" ] || exit 0

# --no-exit because error-level alerts are the case we want to report, and
# without it Vale's nonzero exit would look like a failed run. A failure
# here is a configuration Vale could not load -- in a repository that has
# one -- and saying so beats silence that reads as a clean pass. Stderr goes
# to its own file so a successful run's output stays unmixed.
err=$(mktemp "${TMPDIR:-/tmp}/vale-edit.XXXXXX") || exit 0
if ! alerts=$(cd "$root" && vale --no-exit --output="$tmpl" "$rel" 2>"$err"); then
	# The error's shape: a code line, a styled config excerpt, the message,
	# and an "Execution stopped" trailer. The code and the message are the
	# two lines worth relaying; the excerpt's ANSI styling is stripped.
	esc=$(printf '\033')
	code=$(head -n 1 "$err" | cut -d ' ' -f 1)
	why=$(sed "s/$esc\[[0-9;]*m//g" "$err" |
		grep -v '^[[:space:]]*$' |
		grep -v '^Execution stopped' |
		tail -n 1)
	rm -f "$err"
	emit "Vale could not check this file: ${code:-error}: ${why:-unknown error}"
	exit 0
fi
rm -f "$err"

# Vale's own MinAlertLevel gates what appears in the output at all; this is
# the second gate, over whatever survived the first. A message may itself
# contain tabs, so fields past the third are rejoined.
lines=$(printf '%s\n' "$alerts" | awk -F '\t' -v keep="$keep" '
	NF >= 4 && $1 ~ keep {
		msg = $4
		for (i = 5; i <= NF; i++) msg = msg FS $i
		printf "  line %s: %s [%s] — %s\n", $2, $3, $1, msg
	}
')
[ -n "$lines" ] || exit 0

count=$(printf '%s\n' "$lines" | grep -c .)
if [ "$level" = "error" ]; then
	advice="Fix these before moving on, preserving the markup exactly."
else
	advice="Fix the errors before moving on, preserving the markup exactly; treat the rest as advice."
fi

emit "Vale reports $count alert(s) at $level level or above in this file:
$lines

$advice Do not disable a rule to clear one."
