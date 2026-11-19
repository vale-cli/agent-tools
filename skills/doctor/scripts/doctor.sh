#!/bin/sh
#
# Check a Vale setup end to end and say, for each part, whether it works and
# what to run if it does not.
#
#   doctor.sh [path-to-a-prose-file]
#
# Reads only. Each line starts with "ok", "warn" or "FAIL"; a FAIL line is
# followed by the command that fixes it. Exit status is 1 if anything failed.
#
# POSIX sh and POSIX tools only.
set -u

fails=0
ok() { printf 'ok    %s\n' "$1"; }
warn() { printf 'warn  %s\n' "$1"; [ -z "${2:-}" ] || printf '      -> %s\n' "$2"; }
fail() { printf 'FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '      -> %s\n' "$2"; fails=$((fails + 1)); }
esc=$(printf '\033')
# Paths under the current directory are shown relative to it.
here=$(pwd)
rel() { case "$1" in "$here"/*) printf '%s' "${1#"$here"/}" ;; *) printf '%s' "$1" ;; esac; }
plain() { sed "s/$esc\[[0-9;]*m//g" | grep -v '^[[:space:]]*$'; }

# ---- the binary
if ! command -v vale >/dev/null 2>&1; then
	fail "vale is not on PATH" "run the setup skill's scripts/install.sh, or see https://docs.vale.sh/topics/installation"
	echo
	echo "Nothing else can be checked without the binary."
	exit 1
fi
ok "vale $(vale --version 2>/dev/null | sed 's/^vale version //') at $(command -v vale)"

# ---- the configuration
if ! out=$(vale ls-config 2>&1); then
	if vale --no-global ls-config >/dev/null 2>&1; then
		fail "the project's configuration loads on its own, but not with the user-level one merged in" "vale ls-dirs names that file; if it sets Vocab, remove the line or upgrade Vale"
		echo
		echo "Nothing else can be checked until the configuration loads."
		exit 1
	fi
	why=$(printf '%s\n' "$out" | plain | grep -v '^Execution stopped' | tail -n 1)
	case "$out" in
	*'.vale.ini not found'*) fail "no configuration: $why" "run the onboard skill, or setup" ;;
	*) fail "the configuration does not load: $why" "fix the line it names in .vale.ini, then run this again" ;;
	esac
	echo
	echo "Nothing else can be checked until the configuration loads."
	exit 1
fi
cfg=''
dir=$(pwd)
prev=''
while [ "$dir" != "$prev" ]; do
	for f in .vale.ini _vale.ini; do
		[ -f "$dir/$f" ] && cfg=$dir/$f && break 2
	done
	prev=$dir
	dir=$(dirname "$dir")
done
if [ -n "$cfg" ]; then ok "configuration loads: $(rel "$cfg")"; else ok "configuration loads (user-level only; no .vale.ini in this project)"; fi

# ---- styles on disk
if [ -n "$cfg" ]; then
	root=$(dirname "$cfg")
	sp=$(sed -n 's/^[[:space:]]*StylesPath[[:space:]]*=[[:space:]]*//p' "$cfg" | head -n 1 | tr -d '\r')
	case "$sp" in
	'') sp='' ;;
	/* | [A-Za-z]:*) ;;
	*) sp=$root/$sp ;;
	esac
	if [ -z "$sp" ]; then
		warn "the configuration sets no StylesPath" "add 'StylesPath = styles' above the first [section]"
	elif [ ! -d "$sp" ]; then
		fail "StylesPath $(rel "$sp") does not exist" "vale sync"
	else
		missing=''
		for s in $(sed -n 's/^[[:space:]]*BasedOnStyles[[:space:]]*=[[:space:]]*//p' "$cfg" | tr ',' '\n' |
			sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^Vale$' | grep . | sort -u); do
			[ -d "$sp/$s" ] || missing="$missing $s"
		done
		if [ -n "$missing" ]; then
			fail "styles named in the configuration are not on disk:$missing" "vale sync"
		else
			ok "every style the configuration names is in $(rel "$sp")"
		fi
		vocab=$(sed -n 's/^[[:space:]]*Vocab[[:space:]]*=[[:space:]]*//p' "$cfg" | head -n 1 | tr -d '\r')
		if [ -n "$vocab" ]; then
			for v in $(printf '%s' "$vocab" | tr ',' ' '); do
				if [ -f "$sp/config/vocabularies/$v/accept.txt" ]; then
					ok "vocabulary $v: $(grep -c . "$sp/config/vocabularies/$v/accept.txt") terms accepted"
				else
					fail "vocabulary $v has no accept.txt in $(rel "$sp")/config/vocabularies/$v" "create it, or remove 'Vocab = $v'"
				fi
			done
		else
			warn "no vocabulary: product names will be flagged as misspellings" "the vocab skill"
		fi
		# What git would do with the parts that are source and the parts that are not.
		if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			if [ -n "$vocab" ]; then
				v1=${vocab%%,*}
				if git -C "$root" check-ignore -q "$sp/config/vocabularies/$v1/accept.txt" 2>/dev/null; then
					fail "the vocabulary is ignored by git, so it is not shared" "ignore 'styles/*' and add '!styles/config/' (see the setup skill)"
				else
					ok "the vocabulary is tracked by git"
				fi
			fi
			for d in grammars models; do
				if [ -d "$sp/config/$d" ] && ! git -C "$root" check-ignore -q "$sp/config/$d/x" 2>/dev/null; then
					warn "$(rel "$sp")/config/$d is downloaded by vale sync but not ignored by git" "add 'styles/config/$d/' to .gitignore"
				fi
			done
		fi
	fi
fi

# ---- does it actually lint something
target=${1:-}
if [ -z "$target" ] && [ -n "$cfg" ]; then
	target=$(cd "$(dirname "$cfg")" && find . -type f \( -name '*.md' -o -name '*.mdx' -o -name '*.adoc' -o -name '*.rst' \) \
		-not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/styles/*' 2>/dev/null | head -n 1)
	[ -z "$target" ] || target=$(dirname "$cfg")/${target#./}
fi
if [ -z "$target" ]; then
	warn "no prose file found to try a run on" "pass one: doctor.sh docs/index.md"
elif ! run=$(vale --no-exit --output=line "$target" 2>&1); then
	fail "vale could not lint $(rel "$target"): $(printf '%s\n' "$run" | plain | tail -n 1 | sed "s#$here/##g")"
else
	n=$(printf '%s\n' "$run" | grep -c ':')
	if [ "$n" -eq 0 ]; then
		# Zero alerts is either a clean file or a file no section matches, and
		# Vale does not say which.
		warn "a run on $(rel "$target") reports nothing" "if that is a surprise, check that a [section] glob in the configuration matches this file"
	else
		ok "a run on $(rel "$target") works: $n alerts"
	fi
fi

# ---- the user-level configuration, which no other machine has
if [ -n "$cfg" ]; then
	dirs=$(vale ls-dirs --output=JSON 2>/dev/null)
	key() { printf '%s\n' "$dirs" | sed -n "s/^[[:space:]]*\"$1\":[[:space:]]*\"\(.*\)\",\{0,1\}[[:space:]]*\$/\1/p"; }
	gcfg=$(key '\.vale\.ini')
	gsp=$(key StylesPath)
	if [ -n "$gcfg" ] && [ -f "$gcfg" ] && [ "$gcfg" != "$cfg" ]; then
		# Its own paths and the StyleSources record always differ; anything else is a change.
		settings() {
			awk '/^  "StyleSources": \{/ { skip = 1 } skip { if (/^  \}/) skip = 0; next } !/^  "StyleSources"/' |
				grep -v -F -e "$gcfg" -e "${gsp:-$gcfg}"
		}
		if [ "$(printf '%s\n' "$out" | settings)" = "$(vale --no-global ls-config 2>/dev/null | settings)" ]; then
			ok "the user-level configuration at $gcfg changes nothing here"
		else
			how='compare a run with vale --no-global'
			if [ -n "$target" ] && [ -n "${n:-}" ] && bare=$(vale --no-global --no-exit --output=line "$target" 2>/dev/null); then
				how="a run on $(rel "$target") gives $n alerts with it and $(printf '%s\n' "$bare" | grep -c ':') without (vale --no-global)"
			fi
			warn "a user-level configuration is merged into this one: $gcfg" "it is not in the repository, so CI and other machines run without it; $how"
		fi
	fi
fi

# ---- markup parsers the formats in use need
if [ -n "$cfg" ]; then
	if grep -q -E '^\[.*adoc' "$cfg" && ! command -v asciidoctor >/dev/null 2>&1; then
		fail "the configuration lints AsciiDoc, and asciidoctor is not installed" "gem install asciidoctor"
	fi
	if grep -q -E '^\[.*rst' "$cfg" && ! command -v rst2html >/dev/null 2>&1 && ! command -v rst2html.py >/dev/null 2>&1; then
		fail "the configuration lints reStructuredText, and rst2html is not installed" "pip install docutils"
	fi
fi

# ---- the assistant's hooks
if command -v sh >/dev/null 2>&1; then ok "a POSIX shell is available for the edit hook"; fi
level=${VALE_HOOK_LEVEL:-${CLAUDE_PLUGIN_OPTION_LEVEL:-error}}
ok "the edit hook reports '$level' and above; it stays silent on a file with none"
if [ -n "$cfg" ] && grep -q '^[[:space:]]*\[COMMIT_EDITMSG\]' "$cfg"; then
	hp=$(git config --get core.hooksPath 2>/dev/null)
	if [ -n "$hp" ] || [ -x "$(git rev-parse --git-dir 2>/dev/null)/hooks/commit-msg" ]; then
		ok "commit messages are linted, and this clone has a commit hook"
	else
		warn "commit messages are linted in the configuration, but this clone has no commit hook" "see the commits skill; core.hooksPath is set per clone"
	fi
fi

echo
if [ "$fails" -eq 0 ]; then echo "Nothing is broken."; else echo "$fails thing(s) to fix, marked FAIL above."; fi
[ "$fails" -eq 0 ]
