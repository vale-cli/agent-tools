#!/bin/sh
#
# Score a repository's recent commit messages against the common conventions,
# so the choice of one starts from what the team already does.
#
#   history.sh [-n 50] [-c "Conventional SevenRules ..."]
#
# For each convention it lints the last N non-merge commits with Vale's
# Commits package and counts how many have an error-level alert. The
# convention most of the history already passes is the one that can be
# enforced without arguing; if nothing passes, the history has no convention
# and the team is choosing one, not confirming one.
#
# Everything happens in a temp directory. The repository is only read.
# POSIX sh and POSIX tools, plus vale and git.
set -u

n=50
convs='Conventional SevenRules Gitmoji Go Kernel Jira'
while getopts n:c: opt; do
	case "$opt" in
	n) n=$OPTARG ;;
	c) convs=$OPTARG ;;
	*) echo 'usage: history.sh [-n 50] [-c "Conventional SevenRules ..."]' >&2; exit 2 ;;
	esac
done
case "$n" in
'' | *[!0-9]*) echo "history.sh: -n takes a number" >&2; exit 2 ;;
esac

command -v vale >/dev/null 2>&1 || { echo "history.sh: vale is not on PATH" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "history.sh: not inside a git repository" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/vale-commits.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT INT TERM
command -v cygpath >/dev/null 2>&1 && work=$(cygpath -m "$work")

printf 'StylesPath = %s/styles\nPackages = Commits\n\n[COMMIT_EDITMSG]\nBasedOnStyles = Commits\n' "$work" >"$work/.vale.ini"
if ! vale --no-global --config="$work/.vale.ini" sync >"$work/sync.log" 2>&1; then
	echo "history.sh: could not sync the Commits package:" >&2
	sed "s/$(printf '\033')\[[0-9;]*m//g" "$work/sync.log" | grep -v '^[[:space:]]*$' | tail -n 3 >&2
	exit 2
fi

git rev-list --no-merges -n "$n" HEAD >"$work/shas" 2>/dev/null
total=$(grep -c . "$work/shas")
[ "$total" -gt 0 ] || { echo "history.sh: no commits to read" >&2; exit 2; }
i=0
while read -r sha; do
	i=$((i + 1))
	git log -1 --format=%B "$sha" >"$work/msg.$i"
done <"$work/shas"

echo "Last $total commits (merges left out), failing at error level:"
echo
printf '%-14s %8s   %s\n' Convention failing 'most common reason'
best=''
bestfail=$((total + 1))
for conv in Core $convs; do
	if [ "$conv" = Core ]; then styles=Commits; else styles="Commits, $conv"; fi
	[ "$conv" = Core ] || [ -d "$work/styles/$conv" ] || { printf '%-14s %8s   %s\n' "$conv" - 'not in the Commits package'; continue; }
	printf 'StylesPath = %s/styles\nMinAlertLevel = error\n\n[COMMIT_EDITMSG]\nBasedOnStyles = %s\n' "$work" "$styles" >"$work/c.ini"
	fail=0
	: >"$work/rules"
	j=0
	while [ "$j" -lt "$total" ]; do
		j=$((j + 1))
		out=$(vale --no-global --no-exit --config="$work/c.ini" --output=line --path=COMMIT_EDITMSG <"$work/msg.$j" 2>/dev/null)
		if [ -n "$out" ]; then
			fail=$((fail + 1))
			printf '%s\n' "$out" | cut -d: -f4 | sort -u >>"$work/rules"
		fi
	done
	why=$(sort "$work/rules" | uniq -c | sort -rn | head -n 1 | awk '{ printf "%s (%d)", $2, $1 }')
	if [ "$conv" = Core ]; then label='(core only)'; else label=$conv; fi
	printf '%-14s %5d/%-3d  %s\n' "$label" "$fail" "$total" "$why"
	if [ "$conv" != Core ] && [ "$fail" -lt "$bestfail" ]; then
		bestfail=$fail
		best=$conv
	fi
done

echo
if [ "$total" -lt 10 ]; then
	echo "Too few commits ($total) to say what this repository's convention is. Ask; do not infer."
elif [ -z "$best" ]; then
	echo "Closest: none scored."
elif [ $((bestfail * 4)) -le "$total" ]; then
	echo "Closest: $best — $((total - bestfail)) of $total already pass. Enforcing it confirms what the team does."
elif [ $((bestfail * 2)) -le "$total" ]; then
	echo "Closest: $best, but $bestfail of $total fail. A habit, not yet a convention; ask before enforcing."
else
	echo "Closest: $best, and $bestfail of $total fail it. The history follows no convention; the team is choosing one."
fi
echo "(core only) is the part every convention shares: blank line after the subject, imperative mood, no 'wip'."
