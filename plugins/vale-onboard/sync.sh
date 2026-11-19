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
src=$here/../../skills/onboard/scripts
status=0
for f in preview.sh preview.tmpl survey.sh; do
	if [ "${1:-}" = --check ]; then
		cmp -s "$src/$f" "$here/scripts/$f" || { echo "sync.sh: scripts/$f differs from skills/onboard/scripts/$f" >&2; status=1; }
	else
		cp "$src/$f" "$here/scripts/$f"
	fi
done
[ "$status" -eq 0 ] && [ "${1:-}" = --check ] && echo "in sync"
exit $status
