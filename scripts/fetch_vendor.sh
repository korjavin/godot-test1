#!/bin/sh
##
## FETCH THE VENDORED FACE DETECTOR (bead godot-test1-xtr.12).
##
## Reads web/vendor/mediapipe/vendor.lock, downloads exactly what it names,
## verifies every sha256, and refuses to install anything that does not match.
## With a TARGET argument it then copies the directory into <target>/vendor/ and
## asserts the files arrived — which is how the web export gets them.
##
##   sh scripts/fetch_vendor.sh                # just populate web/vendor/mediapipe
##   sh scripts/fetch_vendor.sh build/web      # ...and install into the export
##
## ONE SCRIPT, TWO CALLERS: `.github/workflows/build.yml` and `./serve.sh`. The
## assertions live here rather than in the workflow so the developer rig and CI
## cannot drift — the whole reason the files are not simply committed.
##
## WHY NOT COMMIT THEM: 11.76 MB of binaries in history is permanent weight on
## every clone and every CI checkout. Fetching at BUILD time and baking the
## result into the image is NOT a runtime CDN: the owner's ruling of 2026-09-06
## is about what the PLAYER'S BROWSER loads, and that is still only ever our own
## nginx (`web/nginx.conf` even gzips it). Nothing here runs on a player's
## machine.
##
## Idempotent: a tree that already matches the lock downloads nothing, so a
## rebuild and a second `./serve.sh` are free.
##
set -eu

DIR="web/vendor/mediapipe"
LOCK="$DIR/vendor.lock"
TARGET="${1:-}"

[ -f "$LOCK" ] || { echo "fetch_vendor: no $LOCK — run me from the repo root" >&2; exit 1; }

# `sha256sum` on Linux (CI), `shasum -a 256` on macOS (the developer rig).
sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

# AND THE DOWNLOADER IS WHICHEVER ONE IS THERE. `barichello/godot-ci:4.5` — the
# container the export runs in — ships wget and NO curl, while a developer's mac
# has curl and usually no wget. Neither is worth installing at build time for one
# download, and picking wrong fails with `curl: not found` and exit 127.
#
# The `_fv_` prefixes are not decoration: POSIX sh has no `local`, and this is
# called from inside a loop whose own variable is `dest` — a plain `dest="$1"`
# here silently rewrites the caller's and the next line builds a doubled path.
fetch_to() {
	_fv_dest="$1"
	_fv_url="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --retry 3 -o "$_fv_dest" "$_fv_url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q --tries=3 -O "$_fv_dest" "$_fv_url"
	else
		echo "::error::fetch_vendor: neither curl nor wget is installed" >&2
		exit 1
	fi
}

# Every `file`/`model` row, as "dest sha src". Comments and blanks dropped here
# so each consumer below is a plain read loop.
rows() {
	awk '$1 == "file" || $1 == "model" { print $1, $2, $3, $4 }' "$LOCK"
}

# Does the tree already satisfy the lock? Answers by exit status.
verify_all() {
	rows | while read -r kind dest sha src; do
		[ -f "$DIR/$dest" ] || exit 1
		[ "$(sha256_of "$DIR/$dest")" = "$sha" ] || exit 1
	done
}

TARBALL_URL=$(awk '$1 == "npm" { print $3 }' "$LOCK")
PKG=$(awk '$1 == "npm" { print $2 }' "$LOCK")

if verify_all; then
	echo "fetch_vendor: $DIR already matches the lock ($PKG)"
else
	echo "fetch_vendor: fetching $PKG"
	TMP=$(mktemp -d)
	trap 'rm -rf "$TMP"' EXIT

	# The npm tarball, once, if any `file` row needs it.
	if [ -n "$(awk '$1 == "file"' "$LOCK")" ]; then
		fetch_to "$TMP/pkg.tgz" "$TARBALL_URL"
		# Members are named explicitly, so nothing outside them is ever written.
		MEMBERS=$(awk '$1 == "file" { printf "%s ", $4 }' "$LOCK")
		# shellcheck disable=SC2086
		tar -xzf "$TMP/pkg.tgz" -C "$TMP" $MEMBERS
	fi

	rows | while read -r kind dest sha src; do
		mkdir -p "$DIR/$(dirname "$dest")"
		if [ "$kind" = "model" ]; then
			fetch_to "$DIR/$dest.part" "$src"
		else
			cp "$TMP/$src" "$DIR/$dest.part"
		fi
		got=$(sha256_of "$DIR/$dest.part")
		if [ "$got" != "$sha" ]; then
			rm -f "$DIR/$dest.part"
			echo "::error::fetch_vendor: $dest sha256 mismatch" >&2
			echo "  expected $sha" >&2
			echo "  got      $got" >&2
			echo "  from     $src" >&2
			exit 1
		fi
		# Renamed only after it verifies, so an interrupted or tampered fetch
		# never leaves a half-file that the next run would accept.
		mv "$DIR/$dest.part" "$DIR/$dest"
		# AND MADE WORLD-READABLE, which is not tidiness. The npm tarball carries
		# its files as 0640; `web/Dockerfile` COPYies them into the image with the
		# mode intact, and nginx's workers run as the `nginx` user — so a 0640 wasm
		# is a 403 to every player, and a 403 is exactly the invisible failure that
		# lands on the centre crop and looks like a working game.
		chmod a+r "$DIR/$dest"
		echo "  ok $dest  $sha"
	done
fi

# Verified once more AFTER the loop, because the loop above runs in a pipeline
# subshell on POSIX sh: an `exit 1` inside it cannot fail this script, and
# without this a mismatch would print its error and carry on to install.
verify_all || { echo "::error::fetch_vendor: $DIR does not match $LOCK" >&2; exit 1; }

[ -n "$TARGET" ] || exit 0

# --- install into the export ------------------------------------------------
# The one directory both deploy targets are cut from, beside the service-worker
# tombstone's own copy. A `cp` that silently copied nothing would ship a build
# whose every player falls back to the centre crop with nothing saying so.
mkdir -p "$TARGET/vendor"
rm -rf "$TARGET/vendor/mediapipe"
cp -r "$DIR" "$TARGET/vendor/mediapipe"
# Readable by all, directories traversable — see the chmod above. Repeated here
# because this is the tree that becomes the image, and it is the one that must
# be right even if the source directory was populated by some other route.
chmod -R a+rX "$TARGET/vendor/mediapipe"
for dest in $(awk '$1 == "file" || $1 == "model" { print $2 }' "$LOCK") LICENSE; do
	[ -s "$TARGET/vendor/mediapipe/$dest" ] || {
		echo "::error::$TARGET/vendor/mediapipe/$dest is missing or empty — the vendored face detector did not reach the export, and every player would silently fall back to the centre crop" >&2
		exit 1
	}
	[ -r "$TARGET/vendor/mediapipe/$dest" ] || {
		echo "::error::$TARGET/vendor/mediapipe/$dest is not world-readable — nginx's workers would answer 403 and every player would silently fall back to the centre crop" >&2
		exit 1
	}
done
echo "fetch_vendor: installed into $TARGET/vendor/mediapipe"
ls -l "$TARGET/vendor/mediapipe" "$TARGET/vendor/mediapipe/wasm"
