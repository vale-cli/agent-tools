#!/bin/sh
#
# Work out which English a project writes in, and install the dictionary
# that enforces it.
#
#   dictionary.sh -d path...             count American and British spellings
#   dictionary.sh [-c .vale.ini] en_GB   install a regional English dictionary
#   dictionary.sh [-c .vale.ini] fr      install another language's dictionary
#
# Vale's built-in dictionary accepts both "color" and "colour", so a project
# gets no spelling noise from either -- and no help keeping to one. A regional
# dictionary makes the other variant a misspelling. It is also a general
# dictionary: it does not know "plugin" or "config" the way the built-in one
# does, so expect the vocabulary to grow when you switch.
#
# For a language other than English the dictionary is what makes spell check
# work at all: Vale carries none, and skips files in a language it has no
# dictionary for. Name the language as the config's `Lang` key does -- fr, de,
# es, pt-BR -- and the files are saved under the name Vale looks for.
#
# The dictionaries are Hunspell files from the `wooorm/dictionaries`
# collection (about ninety languages), downloaded into
# <StylesPath>/config/dictionaries, which is source and belongs in the
# repository. Their licences vary by language; each one's is saved beside it.
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

[ $# -eq 1 ] || { echo "usage: dictionary.sh -d path... | dictionary.sh [-c .vale.ini] <en_GB|fr|de|...>" >&2; exit 2; }
case "$1" in
*[!A-Za-z_-]* | '') echo "dictionary.sh: '$1' is not a language code (en_GB, fr, de, pt-BR)" >&2; exit 2 ;;
esac
# The collection names its folders with a hyphen (en-GB); Hunspell and Vale
# name the files with an underscore (en_GB). American English is plain "en".
name=$(printf '%s' "$1" | tr '-' '_')
src=$(printf '%s' "$1" | tr '_' '-')
case "$name" in
en_US | en) src=en; name=en_US ;;
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

base=https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/$src
for ext in dic aff; do
	if ! curl -fsSL -o "$dest/$name.$ext.part" "$base/index.$ext"; then
		rm -f "$dest/$name.dic.part" "$dest/$name.aff.part" "$dest/$name.dic"
		echo "dictionary.sh: no dictionary for '$src' at $base" >&2
		echo "See https://github.com/wooorm/dictionaries for the languages it has, or put any" >&2
		echo "Hunspell .dic/.aff pair in $dest yourself." >&2
		exit 1
	fi
	mv "$dest/$name.$ext.part" "$dest/$name.$ext"
done
# A .dic file opens with its entry count, sometimes behind a byte-order mark.
# Anything else is an error page saved under a dictionary's name, and Vale
# would then call every word in the language a misspelling.
entries=$(head -n 1 "$dest/$name.dic" | tr -cd '0-9')
[ -n "$entries" ] || {
	rm -f "$dest/$name.dic" "$dest/$name.aff"
	echo "dictionary.sh: what $base served is not a Hunspell dictionary; nothing installed" >&2
	exit 1
}
curl -fsSL -o "$dest/$name.license.txt" "$base/license" 2>/dev/null || rm -f "$dest/$name.license.txt"

echo "Installed $name.dic and $name.aff in $dest ($entries entries)"
[ -f "$dest/$name.license.txt" ] && echo "Licence: $dest/$name.license.txt"
case "$name" in
en_*) echo "Next: a spelling rule that names $name, and Vale.Spelling = NO. See the vocab skill." ;;
*) echo "Next: Lang = $src on the section for those files. Vale.Spelling then uses this dictionary." ;;
esac
