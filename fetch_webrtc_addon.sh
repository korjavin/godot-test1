#!/usr/bin/env bash
#
# Install the desktop WebRTC GDExtension so two Godot editor instances can
# actually join a multiplayer room.
#
# WHY THIS EXISTS: the shipping target is the web build, and browsers bring
# their own WebRTC — nothing to install. Godot's DESKTOP builds ship the WebRTC
# *classes* but no implementation, so `WebRTCPeerConnection.new()` returns null
# and multiplayer can only ever be tested in a browser. The official
# `webrtc-native` GDExtension fills that gap, for development only.
#
# WHY IT IS FETCHED AND NOT VENDORED: the release is a 37 MB zip that unpacks to
# 92 MB of prebuilt binaries for twelve platform/arch combinations, of which one
# machine uses exactly one — and its bundled libraries (libdatachannel, libjuice,
# plog) are MPL-2.0, which attaches source-availability duties to whoever
# *redistributes* the binaries. Committing them would pay both costs, in a repo
# whose production build does not use them at all. `addons/` is gitignored.
#
#     ./fetch_webrtc_addon.sh            # install (no-op if already installed)
#     ./fetch_webrtc_addon.sh --force    # reinstall, e.g. after bumping VERSION
#
set -euo pipefail

# Pinned on purpose: an unpinned "latest" makes two developers' machines
# silently different. Bump all three lines together — the checksum is the whole
# point of pinning, and GitHub publishes it as the asset's `digest` field
# (`gh api repos/godotengine/webrtc-native/releases/tags/<VERSION>`).
VERSION="1.2.1-stable"
ARCHIVE="godot-extension-webrtc_native.zip"
URL="https://github.com/godotengine/webrtc-native/releases/download/${VERSION}/${ARCHIVE}"
SHA256="f37d03da03da3ff0d092542a04586644f889135cb7a1c3566ad57513203a553b"

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dest="${repo_root}/addons/webrtc"
marker="${dest}/webrtc.gdextension"

force=""
if [ "${1:-}" = "--force" ]; then
	force="yes"
elif [ -n "${1:-}" ]; then
	echo "usage: $(basename "$0") [--force]" >&2
	exit 2
fi

if [ -f "$marker" ] && [ -z "$force" ]; then
	echo "Already installed: ${marker}"
	echo "Pass --force to reinstall."
	exit 0
fi

# macOS ships `shasum`, most Linuxes ship `sha256sum`, and neither ships both.
if command -v sha256sum >/dev/null 2>&1; then
	sha_cmd() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
	sha_cmd() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
	echo "error: need sha256sum or shasum to verify the download" >&2
	exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading webrtc-native ${VERSION} (~37 MB)..."
curl -fSL --retry 3 -o "${tmp}/${ARCHIVE}" "$URL"

got="$(sha_cmd "${tmp}/${ARCHIVE}")"
if [ "$got" != "$SHA256" ]; then
	echo "error: checksum mismatch for ${ARCHIVE}" >&2
	echo "  expected ${SHA256}" >&2
	echo "  got      ${got}" >&2
	exit 1
fi
echo "Checksum OK."

unzip -q "${tmp}/${ARCHIVE}" -d "$tmp"

# The archive unpacks to `addons/webrtc_native/webrtc_native.gdextension`, but
# `MPManager.WEBRTC_ADDON_PATH` probes `addons/webrtc/webrtc.gdextension`, so we
# rename both. This is safe because the library paths INSIDE the .gdextension
# are relative to the .gdextension file ("lib/libwebrtc_native.*"), not absolute
# res:// paths — moving the directory wholesale keeps every one of them valid.
mkdir -p "${repo_root}/addons"
rm -rf "$dest"
mv "${tmp}/addons/webrtc_native" "$dest"
mv "${dest}/webrtc_native.gdextension" "$marker"

echo "Installed to ${dest} (gitignored)."

# Verify rather than assume. `--import` first because a fresh clone has no
# .godot/ cache, and without it the project's `class_name` scripts do not
# resolve and the check cannot load the code it is checking.
if command -v godot >/dev/null 2>&1; then
	echo "Verifying..."
	godot --headless --path "$repo_root" --import >/dev/null 2>&1 || true
	godot --headless --path "$repo_root" --script res://scripts/webrtc_addon_check.gd
else
	echo
	echo "godot is not on PATH — verify by hand once it is:"
	echo "  godot --headless --path . --import"
	echo "  godot --headless --path . --script res://scripts/webrtc_addon_check.gd"
fi
