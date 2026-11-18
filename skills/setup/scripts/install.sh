#!/bin/sh
#
# Install Vale and make sure it is on PATH.
#
# Uses a package manager when one that carries Vale is there and can run
# without a password prompt, because that keeps Vale up to date. Otherwise it
# downloads the release binary, verifies it against the release's published
# SHA-256 checksums, and puts it in a directory that is already on PATH.
#
#   install.sh [-b] [-p]
#
#   -b  skip package managers and install the release binary
#   -p  if the install directory is not on PATH, add it to the shell's
#       startup file. Without -p the line to add is printed, not written.
#
#   VALE_VERSION      release to install, e.g. 3.27.0 (default: the latest).
#                     Implies -b: package managers install their own version.
#   VALE_INSTALL_DIR  where the binary goes. Default: the first of
#                     ~/.local/bin, ~/bin, /usr/local/bin that is on PATH and
#                     writable, else ~/.local/bin.
#
# Linux and macOS, x86-64 and arm64. On Windows use `choco install vale`,
# `scoop install vale` or `winget install -e --id errata-ai.Vale`.
set -eu

binary=0
addpath=0
while getopts bp opt; do
	case "$opt" in
	b) binary=1 ;;
	p) addpath=1 ;;
	*) echo "usage: install.sh [-b] [-p]" >&2; exit 2 ;;
	esac
done
[ -z "${VALE_VERSION:-}" ] || binary=1

if command -v vale >/dev/null 2>&1; then
	echo "vale is already installed: $(vale --version) ($(command -v vale))"
	exit 0
fi

fail() {
	echo "install.sh: $1" >&2
	exit 1
}

# A package manager is used only if it can run right now without asking for a
# password: an agent cannot answer a sudo prompt, and a hung install is worse
# than a binary in ~/.local/bin.
elevate=''
can_elevate() {
	[ "$(id -u)" -eq 0 ] && return 0
	command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && elevate='sudo -n' && return 0
	return 1
}
if [ "$binary" -eq 0 ]; then
	if command -v brew >/dev/null 2>&1; then
		echo "Installing Vale with Homebrew…"
		if brew install vale; then
			command -v vale >/dev/null 2>&1 && { echo "Installed $(vale --version) with Homebrew"; exit 0; }
		fi
		echo "Homebrew did not provide vale; falling back to the release binary." >&2
	elif command -v pacman >/dev/null 2>&1 && can_elevate; then
		echo "Installing Vale with pacman…"
		# shellcheck disable=SC2086
		if $elevate pacman -S --noconfirm vale && command -v vale >/dev/null 2>&1; then
			echo "Installed $(vale --version) with pacman"
			exit 0
		fi
		echo "pacman did not provide vale; falling back to the release binary." >&2
	elif command -v snap >/dev/null 2>&1 && can_elevate; then
		echo "Installing Vale with snap…"
		# shellcheck disable=SC2086
		if $elevate snap install vale && command -v vale >/dev/null 2>&1; then
			echo "Installed $(vale --version) with snap"
			exit 0
		fi
		echo "snap did not provide vale; falling back to the release binary." >&2
	fi
fi

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

on_path() {
	case ":$PATH:" in
	*":$1:"*) return 0 ;;
	esac
	return 1
}

# Prefer a directory that is already on PATH, so the binary works in the
# shell that asked for it and in every later one, with nothing to configure.
dest=${VALE_INSTALL_DIR:-}
if [ -z "$dest" ]; then
	for d in "$HOME/.local/bin" "$HOME/bin" /usr/local/bin; do
		if on_path "$d" && [ -d "$d" ] && [ -w "$d" ]; then
			dest=$d
			break
		fi
	done
	[ -n "$dest" ] || dest=$HOME/.local/bin
fi

asset=vale_${version}_${os}_${arch}.tar.gz
base=$repo/releases/download/v$version

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

on_path "$dest" && exit 0

# Not on PATH: name the startup file for the user's shell and the line it
# needs. Writing to someone's shell configuration is opt-in.
case "$(basename "${SHELL:-sh}")" in
zsh) rc=${ZDOTDIR:-$HOME}/.zshrc; line="export PATH=\"$dest:\$PATH\"" ;;
bash)
	rc=$HOME/.bashrc
	[ "$os" = macOS ] && rc=$HOME/.bash_profile
	line="export PATH=\"$dest:\$PATH\""
	;;
fish) rc=$HOME/.config/fish/conf.d/vale.fish; line="fish_add_path $dest" ;;
*) rc=$HOME/.profile; line="export PATH=\"$dest:\$PATH\"" ;;
esac

if [ "$addpath" -eq 1 ]; then
	if [ -f "$rc" ] && grep -qF "$dest" "$rc"; then
		echo "$rc already mentions $dest; left as it is."
	else
		mkdir -p "$(dirname "$rc")"
		printf '\n# Added by the Vale installer\n%s\n' "$line" >>"$rc"
		echo "Added $dest to PATH in $rc."
	fi
	echo "New shells will find vale. In this one, run: $dest/vale"
else
	echo "$dest is not on PATH. To add it, put this line in $rc:"
	echo "  $line"
	echo "Or re-run with -p to have it added. Until then, run: $dest/vale"
fi
