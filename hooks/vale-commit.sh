#!/bin/sh
#
# PostToolUse on Bash: when the assistant has just made a commit in a
# repository that lints its commit messages with Vale, lint that message and
# hand any error-level alerts straight back.
#
# A commit-msg hook does this for people, but core.hooksPath is set per clone
# and an assistant's checkout usually has not run the project's setup. This
# gives the assistant the same check the team's own commits get.
#
# Silent by design, like the edit hook: no Vale, no git, a command that was
# not a commit, a repository whose configuration has no [COMMIT_EDITMSG]
# section, or a message that passes all exit 0 with no output.
#
# It runs after the commit rather than before, because the message is then
# exactly what git recorded -- no parsing of -m flags, heredocs or editor
# files out of a shell command. The commit is normally still local at this
# point, which is when amending its message is safe; the advice says so.
#
# POSIX sh and POSIX tools only.
set -u

command -v vale >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

payload=$(cat)
case "$payload" in
*'git commit'* | *'git -c '*' commit'*) ;;
*) exit 0 ;;
esac

# The session's working directory, from the payload; the hook may be started
# somewhere else.
cwd=$(printf '%s\n' "$payload" |
	sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 |
	sed 's/\\\\/\//g; s/\\\//\//g')
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null
top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$top" || exit 0

# Only a project that opted in: its configuration has the section.
cfg=''
for f in .vale.ini _vale.ini; do
	[ -f "$f" ] && cfg=$f && break
done
[ -n "$cfg" ] || exit 0
grep -q '^[[:space:]]*\[COMMIT_EDITMSG\]' "$cfg" || exit 0

# The command may have failed, or not have been a commit at all ("git commit
# --help", a commit in another repository). Only a commit made in the last
# few seconds is the one this command made.
when=$(git log -1 --format=%ct 2>/dev/null) || exit 0
now=$(date +%s)
[ $((now - when)) -le 15 ] || exit 0

# Messages git writes itself are left alone, as the commit-msg hook does.
subject=$(git log -1 --format=%s)
case "$subject" in
"Merge "* | "Revert "* | "Reapply "* | "fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
esac

# Errors only: they are what the project's own hook would have refused.
alerts=$(git log -1 --format=%B | vale --no-exit --minAlertLevel=error --output=line --path=COMMIT_EDITMSG 2>/dev/null) || exit 0
[ -n "$alerts" ] || exit 0

lines=$(printf '%s\n' "$alerts" | awk -F: 'NF >= 5 {
	msg = $5
	for (i = 6; i <= NF; i++) msg = msg ":" $i
	printf "  line %s: %s — %s\n", $2, $4, msg
}')
[ -n "$lines" ] || exit 0
count=$(printf '%s\n' "$lines" | grep -c .)

printf '%s' "The commit you just made (\"$subject\") has a message that breaks $count of this project's commit rules:
$lines

If it has not been pushed, reword it with 'git commit --amend' so it passes, then carry on. If it has been pushed, leave it and say so; do not rewrite pushed history." | awk '
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
