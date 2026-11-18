#!/bin/sh
#
# Preview a Vale baseline without writing anything to the repository.
#
# Builds a throwaway configuration in a temp directory, syncs the package
# there, lints the given paths, and prints what an onboarding decision needs:
# the counts by severity and by rule, a real example of each of the busiest
# rules, and the terms spell check does not know. Give several packages to
# compare them side by side; give one, with a proposed vocabulary and
# overrides, to see the baseline before anyone commits to it.
#
#   preview.sh [-p Package]... [-a accept.txt] [-o overrides.ini] [-s styledir] path...
#
#   -p  style package to try (default: Microsoft). Repeat it to compare
#       packages. The package and the style it installs must share a name,
#       which holds for the common ones.
#   -a  file of vocabulary terms, one per line, to accept
#   -o  file of per-rule overrides (`Style.Rule = NO`), appended to the section
#   -s  directory of the project's own rules, enabled under its own name
#
# POSIX sh and POSIX tools only, plus vale. No jq: this is the first thing a
# new user runs, and it should not fail on a missing dependency.
set -u

usage='usage: preview.sh [-p Package]... [-a accept.txt] [-o overrides.ini] [-s styledir] path...'
pkgs=''
accept=''
over=''
house=''
while getopts p:a:o:s: opt; do
	case "$opt" in
	p) pkgs="$pkgs $OPTARG" ;;
	a) accept=$OPTARG ;;
	o) over=$OPTARG ;;
	s) house=${OPTARG%/} ;;
	*) echo "$usage" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || { echo "preview.sh: give at least one path to lint" >&2; echo "$usage" >&2; exit 2; }
[ -n "$pkgs" ] || pkgs=Microsoft
# shellcheck disable=SC2086
set_count() { echo $#; }
npkg=$(set_count $pkgs)

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
if [ "$npkg" -gt 1 ] && [ -n "$over" ]; then
	echo "preview.sh: -o names one package's rules; use it with a single -p" >&2
	exit 2
fi
hname=''
[ -z "$house" ] || hname=$(basename "$house")

work=$(mktemp -d "${TMPDIR:-/tmp}/vale-preview.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT INT TERM
esc=$(printf '\033')

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
files=$(printf '%s\n' "$exts" | awk '{ printf "%s%s .%s", (NR > 1 ? ", " : ""), $1, $2 }')

# lint <package> <paths...>: writes $work/<package>.tsv, or explains and fails.
lint() {
	pkg=$1
	shift
	dir=$work/$pkg
	mkdir -p "$dir/styles"
	{
		echo "StylesPath = $dir/styles"
		echo "MinAlertLevel = suggestion"
		echo "Packages = $pkg"
		[ -z "$accept" ] || echo "Vocab = Preview"
		echo
		echo "[$glob]"
		echo "BasedOnStyles = Vale, $pkg${hname:+, $hname}"
		[ -z "$over" ] || { echo; cat "$over"; }
	} >"$dir/.vale.ini"
	if [ -n "$accept" ]; then
		mkdir -p "$dir/styles/config/vocabularies/Preview"
		cp "$accept" "$dir/styles/config/vocabularies/Preview/accept.txt"
	fi
	if [ -n "$house" ]; then
		mkdir -p "$dir/styles/$hname"
		cp "$house"/*.yml "$dir/styles/$hname/"
	fi
	if ! vale --no-global --config="$dir/.vale.ini" sync >"$dir/sync.log" 2>&1; then
		echo "preview.sh: could not sync '$pkg':" >&2
		sed "s/$esc\[[0-9;]*m//g" "$dir/sync.log" | grep -v '^[[:space:]]*$' | tail -n 3 >&2
		return 1
	fi
	if ! vale --no-global --no-exit --config="$dir/.vale.ini" --output="$tmpl" "$@" >"$work/$pkg.tsv" 2>"$dir/err.log"; then
		echo "preview.sh: vale could not run with '$pkg':" >&2
		sed "s/$esc\[[0-9;]*m//g" "$dir/err.log" | grep -v '^[[:space:]]*$' | tail -n 3 >&2
		return 1
	fi
}

# Several packages: one row each, so the choice comes with numbers.
if [ "$npkg" -gt 1 ]; then
	echo "Section:  [$glob]"
	echo "Files:    $files"
	echo
	printf '%-14s %7s %7s %9s %12s\n' Package total errors warnings suggestions
	for p in $pkgs; do
		lint "$p" "$@" || exit 2
		awk -F '\t' -v p="$p" '
			$1 ~ /^(error|warning|suggestion)$/ && NF >= 2 { n++; sev[$1]++ }
			END { printf "%-14s %7d %7d %9d %12d\n", p, n, sev["error"], sev["warning"], sev["suggestion"] }
		' "$work/$p.tsv"
	done
	echo
	echo "Run again with one -p for that package's rules and examples."
	exit 0
fi

pkg=${pkgs# }
lint "$pkg" "$@" || exit 2
out=$work/$pkg.tsv

echo "Package:  $pkg"
echo "Section:  [$glob]"
echo "Files:    $files"
[ -z "$accept" ] || echo "Vocab:    $(grep -c . "$accept") terms accepted"
[ -z "$house" ] || echo "Own rules: $hname ($(find "$house" -maxdepth 1 -name '*.yml' | wc -l | tr -d ' ') files)"
[ -z "$over" ] || echo "Rules:    $(grep -c '^[^#[:space:]].*=' "$over") overrides applied"

awk -F '\t' '
	$1 ~ /^(error|warning|suggestion)$/ && NF >= 2 { n++; sev[$1]++; rule[$2]++; rsev[$2] = $1 }
	END {
		printf "\nTotal:    %d   errors %d · warnings %d · suggestions %d\n", n, sev["error"], sev["warning"], sev["suggestion"]
		printf "Blocking: %s\n\n", (sev["error"] > 0 ? sev["error"] " error-level alerts; a blocking job would fail" : "nothing; a blocking job would pass")
		for (r in rule) printf "%6d  %-10s  %s\n", rule[r], rsev[r], r | "sort -rn"
	}
' "$out"

# One real alert from each of the five busiest rules. A count says how much;
# an example says whether the rule is right for these docs.
awk -F '\t' '
	$1 ~ /^(error|warning|suggestion)$/ && NF >= 5 {
		n[$2]++
		if (!($2 in ex)) ex[$2] = $3 ":" $4 "  " $5
	}
	END { for (r in n) printf "%d\t%s\t%s\n", n[r], r, ex[r] }
' "$out" | sort -rn | head -n 5 | awk -F '\t' '
	NR == 1 { print "\nFrom these docs (one alert per busiest rule):" }
	{ printf "  %s\n    %s\n", $2, $3 }
'

terms=$(awk -F '\t' '$2 == "Vale.Spelling" && NF >= 6 { print $6 }' "$out" | sort | uniq -c | sort -rn)
if [ -n "$terms" ]; then
	printf '\nUnknown to spell check (count, term):\n%s\n' "$terms"
fi
