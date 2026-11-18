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
#   preview.sh [-p Package]... [-a accept.txt] [-o overrides.ini] [-s styledir] [-i scopes] path...
#   preview.sh -k [options] path...          the comments in source code
#   preview.sh -l fr [-d dictdir] path...    prose in another language
#   preview.sh -r path...
#
#   -p  style package to try (default: Microsoft). Repeat it to compare
#       packages. The package and the style it installs must share a name,
#       which holds for the common ones. `-p Vale` is the built-in rules
#       alone -- spelling and repetition -- and is the default with -k or -l,
#       since the style packages are written for English prose.
#   -k  lint source files instead of prose: Vale reads their comments, using
#       the tree-sitter grammar `vale sync` installs for each language found
#   -l  the language the files are written in, as Lang takes it (fr, de,
#       pt-BR). Without a dictionary for it, spell check skips the files.
#   -d  directory of Hunspell .dic/.aff files to spell check with
#   -a  file of vocabulary terms, one per line, to accept
#   -o  file of per-rule overrides (`Style.Rule = NO`), appended to the section
#   -s  directory of the project's own rules, enabled under its own name
#   -i  comma-separated scopes to leave unlinted, added to Vale's defaults:
#       `-i text.frontmatter.id` for front matter fields that are not prose
#   -r  report on the repository's own configuration instead of a temporary
#       one, in the same format, to check an applied baseline against its
#       preview. Takes no other options.
#
# POSIX sh and POSIX tools only, plus vale. No jq: this is the first thing a
# new user runs, and it should not fail on a missing dependency. On Windows it
# runs under Git Bash, like the edit hook.
set -u

usage='usage: preview.sh [-p Package]... [-k] [-l lang] [-d dictdir] [-a accept.txt] [-o overrides.ini] [-s styledir] [-i scopes] path...
       preview.sh -r path...'
pkgs=''
accept=''
over=''
house=''
scopes=''
real=0
code=0
lang=''
dicts=''
while getopts p:a:o:s:i:rkl:d: opt; do
	case "$opt" in
	p) pkgs="$pkgs $OPTARG" ;;
	a) accept=$OPTARG ;;
	o) over=$OPTARG ;;
	s) house=${OPTARG%/} ;;
	i) scopes=$OPTARG ;;
	r) real=1 ;;
	k) code=1 ;;
	l) lang=$OPTARG ;;
	d) dicts=${OPTARG%/} ;;
	*) echo "$usage" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || { echo "preview.sh: give at least one path to lint" >&2; echo "$usage" >&2; exit 2; }
if [ "$real" -eq 1 ] && [ -n "$pkgs$accept$over$house$scopes$lang$dicts" ]; then
	echo "preview.sh: -r reads the repository's configuration and takes no other options" >&2
	exit 2
fi
if [ -z "$pkgs" ]; then
	if [ "$code" -eq 1 ] || [ -n "$lang" ]; then pkgs=Vale; else pkgs=Microsoft; fi
fi
[ -z "$dicts" ] || [ -d "$dicts" ] || { echo "preview.sh: no such directory: $dicts" >&2; exit 2; }
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
# Under Git Bash, /tmp is a path only the shell understands. vale.exe reads
# StylesPath from the config file, where nothing translates it, so the
# directory is named the Windows way from the start.
if command -v cygpath >/dev/null 2>&1; then
	work=$(cygpath -m "$work")
	tmpl=$(cygpath -m "$tmpl")
fi
esc=$(printf '\033')

# The formats actually present decide the section glob. A section that matches
# nothing lints nothing, and Vale does not warn about it.
prose='md mdx markdown adoc rst org txt'
source='go py js jsx mjs cjs ts tsx mts cts java kt kts rs rb c h cpp cc hpp cs swift scala php lua ex exs hs jl css scss sass less proto sh'
if [ "$code" -eq 1 ]; then want=$source; kind=source; else want=$prose; kind=prose; fi
exts=$(find "$@" -type f \
	-not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' \
	-not -path '*/dist/*' -not -path '*/build/*' -not -path '*/target/*' -not -path '*/.venv/*' 2>/dev/null |
	sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' |
	awk -v want="$want" 'BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) ok[w[i]] = 1 } ok[$0]' |
	sort | uniq -c | sort -rn)
[ -n "$exts" ] || { echo "preview.sh: no $kind files under: $*" >&2; exit 2; }
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
		[ "$pkg" = Vale ] || echo "Packages = $pkg"
		[ -z "$lang" ] || echo "Lang = $lang"
		[ -z "$accept" ] || echo "Vocab = Preview"
		# Setting IgnoredScopes replaces Vale's defaults, so they are restated.
		[ -z "$scopes" ] || echo "IgnoredScopes = code, tt, kbd, samp, $scopes"
		echo
		echo "[$glob]"
		if [ "$pkg" = Vale ]; then
			echo "BasedOnStyles = Vale${hname:+, $hname}"
		else
			echo "BasedOnStyles = Vale, $pkg${hname:+, $hname}"
		fi
		[ -z "$over" ] || { echo; cat "$over"; }
	} >"$dir/.vale.ini"
	if [ -n "$accept" ]; then
		mkdir -p "$dir/styles/config/vocabularies/Preview"
		cp "$accept" "$dir/styles/config/vocabularies/Preview/accept.txt"
	fi
	if [ -n "$dicts" ]; then
		mkdir -p "$dir/styles/config/dictionaries"
		cp "$dicts"/*.dic "$dicts"/*.aff "$dir/styles/config/dictionaries/" 2>/dev/null
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
	if ! vale --no-global --no-exit --config="$dir/.vale.ini" --output="$tmpl" "$@" >"$dir/raw.tsv" 2>"$dir/err.log"; then
		echo "preview.sh: vale could not run with '$pkg':" >&2
		sed "s/$esc\[[0-9;]*m//g" "$dir/err.log" | grep -v '^[[:space:]]*$' | tail -n 3 >&2
		return 1
	fi
	# vale.exe writes CRLF when the template was checked out that way.
	tr -d '\r' <"$dir/raw.tsv" >"$work/$pkg.tsv"
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

if [ "$real" -eq 1 ]; then
	out=$work/real.tsv
	if ! vale --no-exit --output="$tmpl" "$@" >"$work/raw.tsv" 2>"$work/err.log"; then
		echo "preview.sh: vale could not run with the repository's configuration:" >&2
		sed "s/$esc\[[0-9;]*m//g" "$work/err.log" | grep -v '^[[:space:]]*$' | tail -n 3 >&2
		exit 2
	fi
	tr -d '\r' <"$work/raw.tsv" >"$out"
	echo "Config:   the repository's own"
else
	pkg=${pkgs# }
	lint "$pkg" "$@" || exit 2
	out=$work/$pkg.tsv
	if [ "$pkg" = Vale ]; then echo "Package:  none (Vale's built-in rules)"; else echo "Package:  $pkg"; fi
	echo "Section:  [$glob]"
	[ -z "$lang" ] || echo "Language: $lang"
	# Vale says so on stderr when it has no dictionary for the language, and
	# then spell check finds nothing: worth repeating where it will be read.
	grep -q 'no dictionary' "$work/$pkg/err.log" 2>/dev/null &&
		echo "Spelling: skipped -- no dictionary for '$lang'; pass one with -d"
fi
echo "Files:    $files"
[ -z "$accept" ] || echo "Vocab:    $(grep -c . "$accept") terms accepted"
[ -z "$house" ] || echo "Own rules: $hname ($(find "$house" -maxdepth 1 -name '*.yml' | wc -l | tr -d ' ') files)"
[ -z "$over" ] || echo "Rules:    $(grep -c '^[^#[:space:]].*=' "$over") overrides applied"
[ -z "$scopes" ] || echo "Unlinted: $scopes"

awk -F '\t' '
	$1 ~ /^(error|warning|suggestion)$/ && NF >= 2 { n++; sev[$1]++; rule[$2]++; rsev[$2] = $1 }
	END {
		printf "\nTotal:    %d   errors %d · warnings %d · suggestions %d\n", n, sev["error"], sev["warning"], sev["suggestion"]
		printf "Blocking: %s\n\n", (sev["error"] > 0 ? sev["error"] " error-level alerts; a blocking job would fail" : "nothing; a blocking job would pass")
		for (r in rule) printf "%6d  %-10s  %s\n", rule[r], rsev[r], r | "sort -rn"
	}
' "$out"

# One real alert from every error-level rule, then from the busiest of the
# rest, eight at most. The error-level rules are the ones that need a
# decision; a count says how much, an example says whether the rule is right.
awk -F '\t' '
	$1 ~ /^(error|warning|suggestion)$/ && NF >= 5 {
		n[$2]++
		if (!($2 in ex)) { ex[$2] = $3 ":" $4 "  " $5; sv[$2] = $1 }
	}
	END { for (r in n) printf "%d\t%d\t%s\t%s\t%s\n", (sv[r] == "error" ? 0 : 1), n[r], r, sv[r], ex[r] }
' "$out" | sort -t "$(printf '\t')" -k1,1n -k2,2rn | head -n 8 | awk -F '\t' '
	NR == 1 { print "\nFrom these docs (one alert per rule: error-level first, then the busiest):" }
	{ printf "  %s (%s, %d)\n    %s\n", $3, $4, $2, $5 }
'

# Each unknown term with where it first appears. A hit in the first lines of
# a file is usually front matter -- an id or a slug, not prose.
terms=$(awk -F '\t' '
	$2 == "Vale.Spelling" && NF >= 6 { n[$6]++; if (!($6 in at)) at[$6] = $3 ":" $4 }
	END { for (t in n) printf "%6d  %-24s %s\n", n[t], t, at[t] }
' "$out" | sort -rn)
if [ -n "$terms" ]; then
	printf '\nUnknown to spell check (count, term, first seen):\n%s\n' "$terms"
fi
