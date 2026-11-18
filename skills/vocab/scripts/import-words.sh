#!/bin/sh
#
# Turn a word list the project already keeps for another spell checker into
# entries for a Vale vocabulary.
#
#   import-words.sh [-a] file...
#
# Reads cspell configuration (JSON or YAML: the `words` list, and
# `cSpell.words` in VS Code settings) and plain word lists, one word per line
# -- .wordlist.txt, .spelling, spelling_wordlist.txt, an aspell personal
# dictionary, a cspell dictionary file. Prints accept.txt entries on stdout;
# it writes nothing itself.
#
# By default it prints only the words Vale's own spell check does not know,
# which is usually a small part of the list: the rest would be clutter in a
# vocabulary. -a prints every word.
#
# Those lists are case-insensitive and a Vale vocabulary is not. An entry
# `kubernetes` would make Vale flag "Kubernetes" as the wrong casing, so an
# all-lowercase word is written as `(?i)kubernetes`, which accepts any casing
# as the original list did. A word that carries capitals is kept as written:
# someone chose that casing, and Vale will hold the docs to it.
#
# POSIX sh and POSIX tools only, plus vale for the default filter.
set -u

all=0
while getopts a opt; do
	case "$opt" in
	a) all=1 ;;
	*) echo "usage: import-words.sh [-a] file..." >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || { echo "usage: import-words.sh [-a] file..." >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/vale-import.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT INT TERM
: >"$work/raw"

for f in "$@"; do
	[ -f "$f" ] || { echo "import-words.sh: no such file: $f" >&2; exit 2; }
	case "$f" in
	*.json | *.jsonc | *.code-workspace)
		# The strings inside every "words", "userWords" or "cSpell.words" array.
		tr '\n\r' '  ' <"$f" | awk '
			{
				s = $0
				while (match(s, /"(words|userWords|cSpell\.words|cSpell\.userWords)"[ \t]*:[ \t]*\[/)) {
					s = substr(s, RSTART + RLENGTH)
					end = index(s, "]")
					if (end == 0) break
					list = substr(s, 1, end - 1)
					while (match(list, /"[^"]*"/)) {
						print substr(list, RSTART + 1, RLENGTH - 2)
						list = substr(list, RSTART + RLENGTH)
					}
					s = substr(s, end + 1)
				}
			}' >>"$work/raw"
		;;
	*.yaml | *.yml)
		# The items under a top-level or nested "words:" key.
		awk '
			/^[ \t]*(words|userWords):[ \t]*$/ { on = 1; next }
			on && /^[ \t]*-[ \t]*/ { w = $0; sub(/^[ \t]*-[ \t]*/, "", w); sub(/[ \t]*#.*$/, "", w); gsub(/^["\047]|["\047]$/, "", w); print w; next }
			on && /^[ \t]*$/ { next }
			{ on = 0 }
		' "$f" | tr -d '\r' >>"$work/raw"
		;;
	*)
		# One word per line. Comments, an aspell header, and cspell entries
		# that forbid a word (!word) are not words to accept.
		tr -d '\r' <"$f" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//' |
			grep -v -E '^(personal_ws-|!|$)' | sed 's/^[*+~]*//; s/[*+]$//' >>"$work/raw"
		;;
	esac
done

# Keep what a vocabulary can hold as a plain term: letters, digits, and the
# marks that occur inside words. Anything else would be read as a pattern.
grep -E "^[[:alpha:]][[:alnum:]'’.-]*$" "$work/raw" | sort -u >"$work/words"
total=$(grep -c . "$work/words")
[ "$total" -gt 0 ] || { echo "import-words.sh: no words found in: $*" >&2; exit 1; }

if [ "$all" -eq 0 ]; then
	command -v vale >/dev/null 2>&1 || { echo "import-words.sh: vale is not on PATH; use -a to skip the filter" >&2; exit 2; }
	w=$work
	command -v cygpath >/dev/null 2>&1 && w=$(cygpath -m "$work")
	mkdir -p "$work/styles"
	printf 'StylesPath = %s/styles\nMinAlertLevel = error\n\n[*.txt]\nBasedOnStyles = Vale\n' "$w" >"$work/.vale.ini"
	printf '{{range .Files}}{{range .Alerts}}{{.Check}}\t{{.Match}}\n{{end}}{{end}}' >"$work/t.tmpl"
	# One word per paragraph, so nothing reads as a repeated word or a sentence.
	sed 'G' "$work/words" >"$work/list.txt"
	if ! vale --no-global --no-exit --config="$w/.vale.ini" --output="$w/t.tmpl" "$w/list.txt" >"$work/flagged" 2>"$work/err"; then
		echo "import-words.sh: vale could not run:" >&2
		tail -n 2 "$work/err" >&2
		exit 2
	fi
	tr -d '\r' <"$work/flagged" | awk -F '\t' '$1 == "Vale.Spelling" { print $2 }' | sort -u >"$work/keep"
	# A flagged match can be part of an entry ("foo-bar" flags "foo"); keep
	# whole entries that contain a flagged word.
	awk 'NR == FNR { k[$0] = 1; next } { n = split($0, p, /[^[:alnum:]\047’]+/); for (i = 1; i <= n; i++) if (p[i] in k) { print; next } }' \
		"$work/keep" "$work/words" >"$work/out"
else
	cp "$work/words" "$work/out"
fi

kept=$(grep -c . "$work/out")
awk '{ if ($0 ~ /[[:upper:]]/) print; else print "(?i)" $0 }' "$work/out"
if [ "$all" -eq 0 ]; then
	echo "import-words.sh: $kept of $total words are unknown to Vale and worth accepting; the rest it already knows." >&2
else
	echo "import-words.sh: $total words." >&2
fi
