#!/bin/sh
#
# Survey a repository for everything Vale could be set up to do there, so an
# onboarding proposal can name each option in a line without anyone having
# gone looking. Reads only; lints nothing and writes nothing.
#
#   survey.sh [dir]
#
# Reports where the prose is, translated docs, source code by language, a
# written style guide, word lists and configs kept for other linters,
# existing CI and hook runners, and whether Vale is already installed or
# configured. Each line is a fact, not a recommendation.
#
# POSIX sh and POSIX tools only. Uses git's file list when there is one, so
# ignored and vendored files are left out.
set -u

root=${1:-.}
cd "$root" 2>/dev/null || { echo "survey.sh: no such directory: $root" >&2; exit 2; }

list=$(mktemp "${TMPDIR:-/tmp}/vale-survey.XXXXXX") || exit 2
trap 'rm -f "$list"' EXIT INT TERM
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	# Tracked files, and new ones not yet added, but nothing git ignores.
	git ls-files -co --exclude-standard >"$list"
fi
if [ ! -s "$list" ]; then
	find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' \
		-not -path '*/dist/*' -not -path '*/build/*' -not -path '*/target/*' | sed 's|^\./||' >"$list"
fi
grep -v -E '(^|/)(node_modules|vendor|third_party|dist|build|target|testdata|fixtures)/' "$list" >"$list.f" && mv "$list.f" "$list"

# ---- Vale itself
if command -v vale >/dev/null 2>&1; then
	echo "Vale:          $(vale --version 2>/dev/null | sed 's/^vale version //') installed"
else
	echo "Vale:          not installed"
fi
cfg=$(grep -E '(^|/)(\.vale\.ini|_vale\.ini)$' "$list" | head -n 3 | tr '\n' ' ')
if [ -n "$cfg" ]; then echo "Config:        $cfg"; else echo "Config:        none"; fi

# ---- Prose, by top directory
echo "Prose:"
grep -E '\.(md|mdx|markdown|adoc|rst|org)$' "$list" | awk -F/ '
	{
		d = (NF == 1 ? "(root)" : (NF == 2 ? $1 : $1 "/" $2))
		ext = $NF; sub(/.*\./, "", ext)
		n[d]++; e[d, ext]++; exts[ext] = 1
	}
	END {
		for (d in n) {
			s = ""
			for (x in exts) if (e[d, x]) s = s (s == "" ? "" : ", ") e[d, x] " ." x
			printf "%d\t  %-28s %s\n", n[d], d, s
		}
	}
' | sort -rn | head -n 6 | cut -f 2-

# ---- Translations: directories named for a language, holding prose
langs='ar|bg|ca|cs|da|de|el|es|et|fa|fi|fr|he|hi|hr|hu|id|it|ja|ko|lt|lv|nb|nl|no|pl|pt|ro|ru|sk|sl|sr|sv|th|tr|uk|vi|zh'
tr=$(grep -E '\.(md|mdx|markdown|adoc|rst|org)$' "$list" |
	grep -E "(^|/)($langs)([-_][A-Za-z]{2,4})?/" |
	sed -E "s#^(.*/)?(($langs)([-_][A-Za-z]{2,4})?)/.*#\1\2#" | sort | uniq -c | sort -rn | head -n 8 |
	awk '{ printf "%s%s (%d)", (NR > 1 ? ", " : ""), $2, $1 }')
echo "Translations:  ${tr:-none found}"

# ---- Source code, by language
code=$(sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' "$list" | awk '
	BEGIN { n = split("go py js jsx ts tsx java kt rs rb c h cpp cc cs swift scala php lua ex exs hs jl proto", w, " "); for (i = 1; i <= n; i++) ok[w[i]] = 1 }
	ok[$0]' | sort | uniq -c | sort -rn | head -n 5 | awk '{ printf "%s%d .%s", (NR > 1 ? ", " : ""), $1, $2 }')
echo "Source code:   ${code:-none}"

# ---- A written style guide
guide=$(grep -i -E '(style[-_ ]?guide|writing[-_ ]?(guide|style)|(^|/)style)[^/]*\.(md|mdx|adoc|rst|txt)$' "$list" |
	grep -v -i -E '(^|/)styles[^/]*$' | head -n 3 | tr '\n' ' ')
echo "Style guide:   ${guide:-none found}"

# ---- What the project already decided, in another tool's format
words=$(grep -E '(^|/)(\.?cspell(\.config)?\.(json|jsonc|ya?ml)|\.wordlist\.txt|wordlist\.txt|\.spelling|spelling_wordlist\.txt|\.aspell\.[a-z]+\.pws|\.github/actions/spelling/allow\.txt)$' "$list" | head -n 4 | tr '\n' ' ')
if [ -z "$words" ] && [ -f .vscode/settings.json ] && grep -q 'cSpell.words' .vscode/settings.json 2>/dev/null; then
	words='.vscode/settings.json (cSpell.words) '
fi
echo "Word lists:    ${words:-none}"
other=$(grep -E '(^|/)(\.markdownlint(-cli2)?\.(json|jsonc|ya?ml|cjs|mjs)|\.markdownlintrc|\.textlintrc(\.(json|ya?ml|js))?|\.codespellrc|\.alexrc(\.(json|ya?ml|js))?|\.proselintrc(\.json)?|\.?commitlint(rc|\.config)[^/]*|\.gitlint|\.languagetool[^/]*)$' "$list" | head -n 6 | tr '\n' ' ')
echo "Other linters: ${other:-none}"

# ---- CI and hooks
if git remote -v 2>/dev/null | grep -q 'github\.com' || grep -q '^\.github/' "$list"; then
	echo "GitHub:        yes"
else
	echo "GitHub:        no sign of it"
fi
ci=''
for f in $(grep -E '^\.github/workflows/[^ ]*\.ya?ml$' "$list"); do
	if grep -q -i -E 'vale-action@|run:.*(^|[^a-z-])vale( |$)' "$f" 2>/dev/null; then
		ci="$ci$f (runs Vale: $(grep -o -i '[a-z-]*/vale-action@[^ ]*' "$f" | head -n 1)) "
	fi
done
[ -n "$ci" ] || ci=$(grep -E '^(\.github/workflows/.*\.ya?ml|\.gitlab-ci\.yml|\.circleci/config\.yml|azure-pipelines\.yml|Jenkinsfile)$' "$list" | head -n 3 | tr '\n' ' ')
echo "CI:            ${ci:-none}"
hooks=$(grep -E '^(\.pre-commit-config\.yaml|lefthook\.yml|\.lefthook\.yml|\.husky/.*)$' "$list" | sed 's|^\.husky/.*|.husky/|' | sort -u | tr '\n' ' ')
hp=$(git config --get core.hooksPath 2>/dev/null)
echo "Hook runner:   ${hooks:-none}${hp:+ (core.hooksPath = $hp)}"

# ---- Leftovers from an older Vale setup
# xargs runs nothing on an empty list; grep given no file would wait on stdin.
old=$(grep -E '\.(sh|bash)$|(^|/)Makefile$' "$list" | tr '\n' '\0' | xargs -0 grep -l -i -w 'vale' 2>/dev/null </dev/null |
	head -n 3 | tr '\n' ' ')
[ -z "$old" ] || echo "Mentions Vale: $old"
exit 0
