#!/bin/sh
#
# Install the Vale binary from its GitHub release, for a machine with no
# package manager that carries it. Verifies the download against the
# release's published SHA-256 checksums before installing anything.
#
#   install.sh
#
#   VALE_VERSION      release to install, e.g. 3.27.0 (default: the latest)
#   VALE_INSTALL_DIR  where the binary goes (default: $HOME/.local/bin)
#
# Linux and macOS, x86-64 and arm64. On Windows use `choco install vale` or
# the zip from the releases page. Prefer `brew install vale` where Homebrew
# exists: it keeps the binary up to date, and this does not.
set -eu

if command -v vale >/dev/null 2>&1; then
	echo "vale is already installed: $(vale --version)"
	exit 0
fi

fail() {
	echo "install.sh: $1" >&2
	exit 1
}
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

case "$(uname -s)" in
Linux) os=Linux ;;
Darwin) os=macOS ;;
*) fail "unsupported system $(uname -s); see https://docs.vale.sh/topics/installation" ;;
esac
case "$(uname -m)" in
x86_64 | amd64) arch=64-bit ;;
arm64 | aarch64) arch=arm64 ;;
*) fail "unsupported architecture $(uname -m); see https://docs.vale.sh/topics/installation" ;;
esac

repo=https://github.com/vale-cli/vale
version=${VALE_VERSION:-}
if [ -z "$version" ]; then
	# The "latest" page redirects to the release's tag, which carries the version.
	url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$repo/releases/latest" 2>/dev/null) ||
		fail "could not find the latest release; set VALE_VERSION (see $repo/releases)"
	version=${url##*/v}
	case "$version" in
	[0-9]*.[0-9]*.[0-9]*) ;;
	*) fail "could not read a version from $url; set VALE_VERSION" ;;
	esac
fi
version=${version#v}

asset=vale_${version}_${os}_${arch}.tar.gz
base=$repo/releases/download/v$version
dest=${VALE_INSTALL_DIR:-$HOME/.local/bin}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/vale-install.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "Downloading Vale $version ($os, $arch)…"
curl -fsSL -o "$tmp/$asset" "$base/$asset" || fail "download failed: $base/$asset"
curl -fsSL -o "$tmp/checksums.txt" "$base/vale_${version}_checksums.txt" ||
	fail "could not download the release checksums; not installing an unverified binary"

want=$(awk -v a="$asset" '$2 == a { print $1 }' "$tmp/checksums.txt")
[ -n "$want" ] || fail "the release checksums do not list $asset"
if command -v sha256sum >/dev/null 2>&1; then
	got=$(sha256sum "$tmp/$asset" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then
	got=$(shasum -a 256 "$tmp/$asset" | awk '{ print $1 }')
else
	fail "need sha256sum or shasum to verify the download"
fi
[ "$got" = "$want" ] || fail "checksum mismatch for $asset; not installing"

tar -xzf "$tmp/$asset" -C "$tmp" vale
mkdir -p "$dest"
mv "$tmp/vale" "$dest/vale"
chmod 755 "$dest/vale"

echo "Installed $("$dest/vale" --version) to $dest/vale (checksum verified)"
case ":$PATH:" in
*":$dest:"*) ;;
*) echo "Note: $dest is not on PATH. Add it, or call $dest/vale directly." ;;
esac
