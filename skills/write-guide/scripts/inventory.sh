#!/bin/sh
#
# List every rule a Vale configuration turns on, at the level it actually
# runs at, with the reason the project gave for changing it.
#
# This is the factual half of a written style guide: which rules exist, which
# block, and which were switched off and why. It is read from the files, not
# recalled, so the guide cannot drift from the configuration.
#
#   inventory.sh [-c .vale.ini] [-f tsv|md|mdx|adoc|rst|org|html]
#
# Columns: rule, level (or "off"), message, reason, link.
#
# The reason is the comment written directly above a rule's override in the
# config. Levels are per rule across the whole config: a project that sets one
# rule differently in two sections gets the last one, which is worth knowing
# before trusting the table for such a project.
#
# POSIX sh and POSIX tools only. Vale's built-in rules (Vale.Spelling,
# Vale.Terms, Vale.Repetition, Vale.Avoid) have no file to read and are not
# listed.
set -u

cfg=.vale.ini
fmt=tsv
while getopts c:f: opt; do
	case "$opt" in
	c) cfg=$OPTARG ;;
	f) fmt=$OPTARG ;;
	*) echo "usage: inventory.sh [-c .vale.ini] [-f tsv|md|mdx|adoc|rst|org|html]" >&2; exit 2 ;;
	esac
done
case "$fmt" in
tsv | md | mdx | adoc | rst | org | html) ;;
*) echo "inventory.sh: unknown format '$fmt' (tsv, md, mdx, adoc, rst, org, html)" >&2; exit 2 ;;
esac
[ -f "$cfg" ] || { echo "inventory.sh: no config at $cfg" >&2; exit 2; }

root=$(dirname "$cfg")
sp=$(sed -n 's/^[[:space:]]*StylesPath[[:space:]]*=[[:space:]]*//p' "$cfg" | head -n 1 | tr -d '\r')
[ -n "$sp" ] || { echo "inventory.sh: $cfg sets no StylesPath" >&2; exit 2; }
case "$sp" in
/*) ;;
*) sp=$root/$sp ;;
esac
[ -d "$sp" ] || { echo "inventory.sh: StylesPath $sp does not exist; run 'vale sync' first" >&2; exit 2; }

styles=$(sed -n 's/^[[:space:]]*BasedOnStyles[[:space:]]*=[[:space:]]*//p' "$cfg" |
	tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^Vale$' | grep . | sort -u)
[ -n "$styles" ] || { echo "inventory.sh: $cfg enables no styles besides Vale" >&2; exit 2; }

tmp=$(mktemp "${TMPDIR:-/tmp}/vale-inventory.XXXXXX") || exit 2
trap 'rm -f "$tmp" "$tmp.o"' EXIT INT TERM

# Overrides: "Style.Rule = value", with the comment block directly above as
# the reason. A blank line ends a comment block.
awk '
	/^[[:space:]]*[#;]/ { c = $0; sub(/^[[:space:]]*[#;][[:space:]]*/, "", c); why = (why == "" ? c : why " " c); next }
	/^[[:space:]]*[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+[[:space:]]*=/ {
		split($0, kv, "="); k = kv[1]; v = kv[2]
		gsub(/[[:space:]]/, "", k); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
		printf "%s\t%s\t%s\n", k, v, why
		why = ""; next
	}
	{ why = "" }
' "$cfg" >"$tmp.o"

# One top-level key from a rule file, unquoted.
key() {
	sed -n "s/^$1:[[:space:]]*//p" "$2" | head -n 1 | tr -d '\r' |
		sed "s/^\"\(.*\)\"\$/\1/; s/^'\(.*\)'\$/\1/"
}

for s in $styles; do
	[ -d "$sp/$s" ] || { echo "inventory.sh: style '$s' is not in $sp; run 'vale sync'" >&2; continue; }
	for f in "$sp/$s"/*.yml; do
		[ -f "$f" ] || continue
		case "$f" in *.test.yml) continue ;; esac
		rule=$s.$(basename "$f" .yml)
		level=$(key level "$f")
		msg=$(key message "$f" | tr '\t' ' ')
		link=$(key link "$f")
		o=$(awk -F '\t' -v r="$rule" '$1 == r { v = $2; w = $3 } END { if (v != "") print v "\t" w }' "$tmp.o")
		why=''
		if [ -n "$o" ]; then
			v=$(printf '%s' "$o" | cut -f 1)
			why=$(printf '%s' "$o" | cut -f 2)
			case "$v" in
			NO | no | No) level=off ;;
			YES | yes | Yes) ;;
			*) level=$v ;;
			esac
		fi
		printf '%s\t%s\t%s\t%s\t%s\n' "$rule" "${level:-warning}" "$msg" "$why" "$link"
	done
done | awk -F '\t' '
	BEGIN { o["error"] = 1; o["warning"] = 2; o["suggestion"] = 3; o["off"] = 4 }
	{ printf "%d\t%s\n", ($2 in o ? o[$2] : 5), $0 }
' | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f 2- >"$tmp"

case "$fmt" in
tsv) cat "$tmp" ;;
md | mdx)
	echo "| Rule | Level | What it says | Why we changed it |"
	echo "|---|---|---|---|"
	awk -F '\t' '{ m = $3; gsub(/\|/, "\\|", m); w = $4; gsub(/\|/, "\\|", w); printf "| `%s` | %s | %s | %s |\n", $1, $2, m, w }' "$tmp"
	;;
adoc)
	echo '[cols="2,1,4,3",options="header"]'
	echo '|==='
	echo '|Rule |Level |What it says |Why we changed it'
	awk -F '\t' '{ m = $3; gsub(/\|/, "\\|", m); w = $4; gsub(/\|/, "\\|", w); printf "\n|`%s`\n|%s\n|%s\n|%s\n", $1, $2, m, w }' "$tmp"
	echo '|==='
	;;
rst)
	echo '.. list-table::'
	echo '   :header-rows: 1'
	echo
	echo '   * - Rule'
	echo '     - Level'
	echo '     - What it says'
	echo '     - Why we changed it'
	awk -F '\t' '{ printf "   * - ``%s``\n     - %s\n     - %s\n     - %s\n", $1, $2, $3, $4 }' "$tmp"
	;;
org)
	echo "| Rule | Level | What it says | Why we changed it |"
	echo "|------+-------+--------------+-------------------|"
	awk -F '\t' '{ m = $3; gsub(/\|/, "\\vert{}", m); w = $4; gsub(/\|/, "\\vert{}", w); printf "| ~%s~ | %s | %s | %s |\n", $1, $2, m, w }' "$tmp"
	;;
html)
	echo '<table>'
	echo '  <thead><tr><th>Rule</th><th>Level</th><th>What it says</th><th>Why we changed it</th></tr></thead>'
	echo '  <tbody>'
	awk -F '\t' '
		function h(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
		{ printf "    <tr><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td></tr>\n", h($1), h($2), h($3), h($4) }
	' "$tmp"
	echo '  </tbody>'
	echo '</table>'
	;;
esac
