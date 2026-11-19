#!/bin/sh
#
# Keep this plugin's copies of the onboarding scripts identical to the main
# plugin's. A plugin is installed on its own, so it cannot reach into
# skills/; the copies are the price of that.
#
#   sync.sh          copy the originals here
#   sync.sh --check  exit 1 if any copy differs
set -eu

here=$(cd "$(dirname "$0")" && pwd)
skills=$here/../../skills
status=0
for f in onboard/scripts/preview.sh onboard/scripts/preview.tmpl onboard/scripts/survey.sh ci/scripts/ci.sh; do
	name=$(basename "$f")
	if [ "${1:-}" = --check ]; then
		cmp -s "$skills/$f" "$here/scripts/$name" || { echo "sync.sh: scripts/$name differs from skills/$f" >&2; status=1; }
	else
		cp "$skills/$f" "$here/scripts/$name"
	fi
done
[ "$status" -eq 0 ] && [ "${1:-}" = --check ] && echo "in sync"
exit $status
