#!/bin/sh
#
# Print the files that run Vale automatically: a GitHub Actions workflow, or a
# pre-commit entry. It prints; it does not write, so what goes into the
# repository is still a decision someone looks at first.
#
#   ci.sh detect
#   ci.sh action [-b] [-r] [-f path]...
#   ci.sh pre-commit [-f path] [-v version]
#
# detect      what is already there: a workflow that runs Vale, a pre-commit
#             config and whether it has Vale in it, and whether this looks
#             like a GitHub repository
# action      a workflow for .github/workflows/vale.yml
#   -b        blocking: fail the job on an error-level alert. Without it the
#             job is advisory and always passes.
#   -r        post alerts as review comments, with one-click suggested fixes.
#             Does not work on pull requests from forks.
#   -f path   what to lint; repeat for several. Default: the repository root,
#             which is rarely what you want.
# pre-commit  the entry for .pre-commit-config.yaml
#   -f path   lint only files under this path
#   -v ver    the Vale release to pin (default: the installed one)
#
# The workflow adds the parser a format needs when the Vale configuration in
# the current directory lints AsciiDoc or reStructuredText.
#
# POSIX sh and POSIX tools only.
set -u

usage() {
	echo 'usage: ci.sh detect | ci.sh action [-b] [-r] [-f path]... | ci.sh pre-commit [-f path] [-v version]' >&2
	exit 2
}
[ $# -gt 0 ] || usage
mode=$1
shift

cfg=''
for f in .vale.ini _vale.ini; do
	[ -f "$f" ] && cfg=$f && break
done

case "$mode" in
detect)
	if git remote -v 2>/dev/null | grep -q 'github\.com' || [ -d .github ]; then
		echo "GitHub:      yes"
	else
		echo "GitHub:      no sign of it (no github.com remote, no .github directory)"
	fi
	found=''
	for f in .github/workflows/*.yml .github/workflows/*.yaml; do
		[ -f "$f" ] || continue
		if grep -q -E 'vale-action@|run:.*(^|[^a-z-])vale( |$)' "$f"; then
			uses=$(grep -o '[A-Za-z-]*/vale-action@[^ ]*' "$f" | head -n 1)
			block='advisory'
			grep -q -E 'fail_on_error:[[:space:]]*true|fail_level:' "$f" && block='blocking'
			trigger=$(grep -E '^on:|^"on":|^  (push|pull_request)' "$f" | tr -d '\n' | tr -s ' ' | cut -c1-60)
			found="$found$f ($uses, $block; $trigger) "
		fi
	done
	echo "Workflow:    ${found:-none runs Vale}"
	if [ -f .pre-commit-config.yaml ]; then
		if grep -q 'vale-cli/vale\|errata-ai/vale' .pre-commit-config.yaml; then
			rev=$(awk '/vale-cli\/vale|errata-ai\/vale/ { f = 1 } f && /rev:/ { print $2; exit }' .pre-commit-config.yaml)
			echo "pre-commit:  .pre-commit-config.yaml has Vale (rev ${rev:-unknown})"
		else
			echo "pre-commit:  .pre-commit-config.yaml exists, without Vale"
		fi
	else
		echo "pre-commit:  not used here (no .pre-commit-config.yaml)"
	fi
	if [ -n "$cfg" ]; then echo "Vale config: $cfg"; else echo "Vale config: none; set Vale up before wiring it into anything"; fi
	;;

action)
	blocking=0
	review=0
	paths=''
	n=0
	while getopts brf: opt; do
		case "$opt" in
		b) blocking=1 ;;
		r) review=1 ;;
		f)
			paths="$paths\"$OPTARG\", "
			one=$OPTARG
			n=$((n + 1))
			;;
		*) usage ;;
		esac
	done
	echo 'name: Vale'
	echo 'on: [pull_request]'
	echo
	echo 'jobs:'
	echo '  vale:'
	echo '    runs-on: ubuntu-latest'
	echo '    steps:'
	echo '      - uses: actions/checkout@v4'
	# A section such as [*.adoc] or [*.{md,rst}] means Vale will need that
	# format's parser on the runner.
	if [ -n "$cfg" ] && grep -q -E '^\[.*adoc' "$cfg"; then
		echo '      - name: Install Asciidoctor'
		echo '        run: sudo apt-get install -y asciidoctor'
	fi
	if [ -n "$cfg" ] && grep -q -E '^\[.*rst' "$cfg"; then
		echo '      - name: Install docutils'
		echo '        run: sudo apt-get install -y docutils'
	fi
	echo '      - uses: vale-cli/vale-action@v3'
	if [ "$n" -gt 0 ] || [ "$blocking" -eq 1 ] || [ "$review" -eq 1 ]; then
		echo '        with:'
	fi
	if [ "$n" -eq 1 ]; then
		echo "          files: $one"
	elif [ "$n" -gt 1 ]; then
		echo "          files: '[${paths%, }]'"
	fi
	[ "$blocking" -eq 0 ] || echo '          fail_on_error: true'
	[ "$review" -eq 0 ] || echo '          reporter: github-pr-review'
	{
		echo "ci.sh: save as .github/workflows/vale.yml"
		if [ "$blocking" -eq 1 ]; then
			echo "ci.sh: blocking - fails on an error-level alert in the lines a pull request adds"
		else
			echo "ci.sh: advisory - reports on the lines a pull request adds, and always passes"
		fi
		[ "$n" -gt 0 ] || echo "ci.sh: no -f given, so it lints the whole repository; name the docs path"
		[ "$review" -eq 0 ] || echo "ci.sh: review comments need a token that can write, which a fork's pull request does not have"
	} >&2
	;;

pre-commit)
	path=''
	version=''
	while getopts f:v: opt; do
		case "$opt" in
		f) path=${OPTARG%/} ;;
		v) version=${OPTARG#v} ;;
		*) usage ;;
		esac
	done
	if [ -z "$version" ]; then
		version=$(vale --version 2>/dev/null | sed -n 's/^vale version //p')
		[ -n "$version" ] || {
			echo "ci.sh: vale is not installed, so there is no version to pin; pass -v (see https://github.com/vale-cli/vale/releases)" >&2
			exit 2
		}
	fi
	# A whole file when there is none yet; the one entry to add when there is.
	[ -f .pre-commit-config.yaml ] || echo 'repos:'
	echo '  - repo: https://github.com/vale-cli/vale'
	echo "    rev: v$version"
	echo '    hooks:'
	echo '      - id: vale'
	echo '        name: vale sync'
	echo '        pass_filenames: false'
	echo '        args: [sync]'
	echo '      - id: vale'
	echo '        args: [--output=line, --minAlertLevel=error]'
	[ -z "$path" ] || echo "        files: ^$path/"
	{
		if [ -f .pre-commit-config.yaml ]; then
			echo "ci.sh: .pre-commit-config.yaml exists - add this entry under its 'repos:' list"
		else
			echo "ci.sh: save as .pre-commit-config.yaml, then each contributor runs 'pre-commit install' once"
		fi
		echo "ci.sh: it stops a commit on error-level alerts only; warnings and suggestions stay out of the way"
	} >&2
	;;

*) usage ;;
esac
