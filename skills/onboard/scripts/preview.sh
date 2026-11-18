#!/bin/sh
#
# Preview a Vale baseline without writing anything to the repository.
#
# Builds a throwaway configuration in a temp directory, syncs the package
# there, lints the given paths, and prints the counts an onboarding decision
# needs: by severity, by rule, and the terms spell check does not know. Run it
# once per candidate package to compare them, then again with a proposed
# vocabulary and overrides to see the baseline before anyone commits to it.
#
#   preview.sh [-p Package] [-a accept.txt] [-o overrides.ini] [-s styledir] path...
#
#   -p  style package to try (default: Microsoft). The package and the style
#       it installs must share a name, which holds for the common ones.
#   -a  file of vocabulary terms, one per line, to accept
#   -o  file of per-rule overrides (`Style.Rule = NO`), appended to the section
#   -s  directory of the project's own rules, enabled under its own name
#
# POSIX sh and POSIX tools only, plus vale. No jq: this is the first thing a
# new user runs, and it should not fail on a missing dependency.
set -u

pkg=Microsoft
accept=''
over=''
house=''
while getopts p:a:o:s: opt; do
	case "$opt" in
	p) pkg=$OPTARG ;;
	a) accept=$OPTARG ;;
	o) over=$OPTARG ;;
	s) house=${OPTARG%/} ;;
	*) echo "usage: preview.sh [-p Package] [-a accept.txt] [-o overrides.ini] [-s styledir] path..." >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || { echo "preview.sh: give at least one path to lint" >&2; exit 2; }

command -v vale >/dev/null 2>&1 || {
	echo "preview.sh: vale is not on PATH. Install it first: https://docs.vale.sh/topics/installation" >&2
	exit 2
}
tmpl=$(dirname "$0")/preview.tmpl
[ -f "$tmpl" ] || { echo "preview.sh: preview.tmpl is missing beside this script" >&2; exit 2; }
for f in "$accept" "$over"; do
	[ -z "$f" ] || [ -f "$f" ] || { echo "preview.sh: no such file: $f" >&2; exit 2; }
done
[ -z "$house" ] || [ -d "$house" ] || { echo "preview.sh: no such directory: $house" >&2; exit 2; }
hname=''
[ -z "$house" ] || hname=$(basename "$house")

work=$(mktemp -d "${TMPDIR:-/tmp}/vale-preview.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT INT TERM

# The formats actually present decide the section glob. A section that matches
# nothing lints nothing, and Vale does not warn about it.
exts=$(find "$@" -type f \( -name '*.md' -o -name '*.mdx' -o -name '*.markdown' \
	-o -name '*.adoc' -o -name '*.rst' -o -name '*.org' -o -name '*.txt' \) \
	-not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' 2>/dev/null |
	sed 's/.*\.//' | sort | uniq -c | sort -rn)
[ -n "$exts" ] || { echo "preview.sh: no prose files (md, mdx, adoc, rst, org, txt) under: $*" >&2; exit 2; }
list=$(printf '%s\n' "$exts" | awk '{ printf "%s%s", (NR > 1 ? "," : ""), $2 }')
case "$list" in
*,*) glob="*.{$list}" ;;
*) glob="*.$list" ;;
esac

{
	echo "StylesPath = $work/styles"
	echo "MinAlertLevel = suggestion"
	echo "Packages = $pkg"
	[ -z "$accept" ] || echo "Vocab = Preview"
	echo
	echo "[$glob]"
	echo "BasedOnStyles = Vale, $pkg${hname:+, $hname}"
	[ -z "$over" ] || { echo; cat "$over"; }
} >"$work/.vale.ini"

if [ -n "$accept" ]; then
	mkdir -p "$work/styles/config/vocabularies/Preview"
	cp "$accept" "$work/styles/config/vocabularies/Preview/accept.txt"
fi

if [ -n "$house" ]; then
	mkdir -p "$work/styles/$hname"
	cp "$house"/*.yml "$work/styles/$hname/"
fi

if ! vale --no-global --config="$work/.vale.ini" sync >"$work/sync.log" 2>&1; then
	echo "preview.sh: could not sync '$pkg':" >&2
	sed "s/$(printf '\033')\[[0-9;]*m//g" "$work/sync.log" | grep -v '^[[:space:]]*$' | tail -n 3 >&2
	exit 2
fi

if ! vale --no-global --no-exit --config="$work/.vale.ini" --output="$tmpl" "$@" >"$work/alerts.tsv" 2>"$work/err.log"; then
	echo "preview.sh: vale could not run:" >&2
	sed "s/$(printf '\033')\[[0-9;]*m//g" "$work/err.log" | grep -v '^[[:space:]]*$' | tail -n 3 >&2
	exit 2
fi

echo "Package:  $pkg"
echo "Section:  [$glob]"
printf 'Files:    %s\n' "$(printf '%s\n' "$exts" | awk '{ printf "%s%s .%s", (NR > 1 ? ", " : ""), $1, $2 }')"
[ -z "$accept" ] || echo "Vocab:    $(grep -c . "$accept") terms accepted"
[ -z "$house" ] || echo "Own rules: $hname ($(ls "$house"/*.yml | wc -l | tr -d ' ') files)"
[ -z "$over" ] || echo "Rules:    $(grep -c '^[^#[:space:]].*=' "$over") overrides applied"

awk -F '\t' '
	NF >= 2 { n++; sev[$1]++; rule[$2]++; rsev[$2] = $1 }
	END {
		printf "\nTotal:    %d   errors %d · warnings %d · suggestions %d\n", n, sev["error"], sev["warning"], sev["suggestion"]
		printf "Blocking: %s\n\n", (sev["error"] > 0 ? sev["error"] " error-level alerts; a blocking job would fail" : "nothing; a blocking job would pass")
		for (r in rule) printf "%6d  %-10s  %s\n", rule[r], rsev[r], r | "sort -rn"
	}
' "$work/alerts.tsv"

terms=$(awk -F '\t' '$2 == "Vale.Spelling" { print $3 }' "$work/alerts.tsv" | sort | uniq -c | sort -rn)
if [ -n "$terms" ]; then
	printf '\nUnknown to spell check (count, term):\n%s\n' "$terms"
fi
