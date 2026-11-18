#!/bin/sh
#
# Work out which English a project writes in, and install the dictionary
# that enforces it.
#
#   dictionary.sh -d path...        count American and British spellings
#   dictionary.sh [-c .vale.ini] en_GB    install that dictionary
#
# Vale's built-in dictionary accepts both "color" and "colour", so a project
# gets no spelling noise from either -- and no help keeping to one. A regional
# dictionary makes the other variant a misspelling. It is also a general
# dictionary: it does not know "plugin" or "config" the way the built-in one
# does, so expect the vocabulary to grow when you switch.
#
# Dictionaries: en_GB, en_AU, en_CA, en_ZA, en_US. They are the Hunspell
# files LibreOffice ships, downloaded into <StylesPath>/config/dictionaries,
# which is source and belongs in the repository. Their licences vary by
# dictionary (LGPL, BSD, MIT and others); the readme is downloaded alongside.
#
# POSIX sh and POSIX tools only, plus curl for the download.
set -u

cfg=.vale.ini
detect=0
while getopts c:d opt; do
	case "$opt" in
	c) cfg=$OPTARG ;;
	d) detect=1 ;;
	*) echo "usage: dictionary.sh -d path... | dictionary.sh [-c .vale.ini] en_GB" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

if [ "$detect" -eq 1 ]; then
	[ $# -gt 0 ] || { echo "dictionary.sh: give at least one path to read" >&2; exit 2; }
	# A fixed list of common pairs. Enough to say which way a corpus leans;
	# not a spell checker.
	us='color|colors|behavior|behaviors|favorite|flavor|honor|labor|center|centers|meter|liter|organize|organized|organization|organizations|recognize|recognized|customize|customized|analyze|analyzed|license|licensed|defense|catalog|dialog|program|programs|canceled|traveled|modeling|labeled|gray|fulfill|enrollment'
	uk='colour|colours|behaviour|behaviours|favourite|flavour|honour|labour|centre|centres|metre|litre|organise|organised|organisation|organisations|recognise|recognised|customise|customised|analyse|analysed|licence|licenced|defence|catalogue|dialogue|programme|programmes|cancelled|travelled|modelling|labelled|grey|fulfil|enrolment'
	files=$(find "$@" -type f \( -name '*.md' -o -name '*.mdx' -o -name '*.markdown' \
		-o -name '*.adoc' -o -name '*.rst' -o -name '*.org' -o -name '*.txt' \) \
		-not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' 2>/dev/null)
	[ -n "$files" ] || { echo "dictionary.sh: no prose files under: $*" >&2; exit 2; }
	count() {
		printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -ohwiE "$1" 2>/dev/null | wc -l | tr -d ' '
	}
	top() {
		printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -ohwiE "$1" 2>/dev/null |
			tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn | head -n 4 |
			awk '{ printf "%s%s (%d)", (NR > 1 ? ", " : ""), $2, $1 }'
	}
	a=$(count "$us")
	b=$(count "$uk")
	echo "American spellings: $a   $(top "$us")"
	echo "British spellings:  $b   $(top "$uk")"
	# "program", "license" and "dialog" are also correct British English in
	# computing, so a British corpus still scores some American hits.
	if [ "$a" -eq 0 ] && [ "$b" -eq 0 ]; then
		echo "Leaning: no evidence either way; leave the built-in dictionary."
	elif [ "$b" -gt $((a * 2)) ]; then
		echo "Leaning: British. en_GB would enforce it."
	elif [ "$a" -gt $((b * 2)) ]; then
		echo "Leaning: American. The built-in dictionary is fine; en_US would enforce it."
	else
		echo "Leaning: mixed. Ask which the team intends before enforcing either."
	fi
	exit 0
fi

[ $# -eq 1 ] || { echo "usage: dictionary.sh -d path... | dictionary.sh [-c .vale.ini] en_GB" >&2; exit 2; }
dict=$1
case "$dict" in
en_GB | en_AU | en_CA | en_ZA | en_US) ;;
*)
	echo "dictionary.sh: '$dict' is not one this script fetches (en_GB, en_AU, en_CA, en_ZA, en_US)." >&2
	echo "Any Hunspell .dic/.aff pair works: put it in <StylesPath>/config/dictionaries yourself." >&2
	exit 2
	;;
esac
[ -f "$cfg" ] || { echo "dictionary.sh: no config at $cfg; set Vale up first" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "dictionary.sh: curl is required" >&2; exit 2; }

sp=$(sed -n 's/^[[:space:]]*StylesPath[[:space:]]*=[[:space:]]*//p' "$cfg" | head -n 1 | tr -d '\r')
[ -n "$sp" ] || { echo "dictionary.sh: $cfg sets no StylesPath" >&2; exit 2; }
case "$sp" in
/* | [A-Za-z]:*) ;;
*) sp=$(dirname "$cfg")/$sp ;;
esac
dest=$sp/config/dictionaries
mkdir -p "$dest"

base=https://raw.githubusercontent.com/LibreOffice/dictionaries/master/en
for ext in dic aff; do
	curl -fsSL -o "$dest/$dict.$ext.part" "$base/$dict.$ext" || {
		rm -f "$dest/$dict.$ext.part"
		echo "dictionary.sh: could not download $base/$dict.$ext" >&2
		exit 1
	}
	mv "$dest/$dict.$ext.part" "$dest/$dict.$ext"
done
# A .dic file opens with its entry count, sometimes behind a byte-order mark.
entries=$(head -n 1 "$dest/$dict.dic" | tr -cd '0-9')
[ -n "$entries" ] || {
	echo "dictionary.sh: $dest/$dict.dic does not look like a Hunspell dictionary" >&2
	exit 1
}
curl -fsSL -o "$dest/README_$dict.txt" "$base/README_$dict.txt" 2>/dev/null ||
	rm -f "$dest/README_$dict.txt"

echo "Installed $dict.dic and $dict.aff in $dest ($entries entries)"
[ -f "$dest/README_$dict.txt" ] && echo "Licence and credits: $dest/README_$dict.txt"
echo "Next: a spelling rule that names it, and Vale.Spelling = NO. See the vocab skill."
