#!/bin/sh
# Clone the patched forks and cross-compile both static arm64 binaries into dist/.
# Requires Go (>= the version in each repo's go.mod) and git on the build host.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck disable=SC1091
. "$HERE/lib.sh"

mkdir -p "$ROOT/build" "$ROOT/dist"

clone() { # clone <repo> <ref> <dir>
	if [ -d "$ROOT/build/$3/.git" ]; then
		git -C "$ROOT/build/$3" fetch --depth 1 origin "$2" && git -C "$ROOT/build/$3" checkout -q FETCH_HEAD
	else
		git clone --depth 1 -b "$2" "$1" "$ROOT/build/$3"
	fi
}

echo "== fetch sources =="
clone "$BRIDGE_REPO" "$BRIDGE_REF" quasar-bridge
clone "$WAKEWORD_REPO" "$WAKEWORD_REF" station-wakeword

echo "== build quasar-bridge (linux/arm64, static) =="
( cd "$ROOT/build/quasar-bridge" && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
	go build -trimpath -ldflags="-s -w" -o "$ROOT/dist/quasar-bridge.arm64" ./cmd/quasar-bridge )

echo "== build station-wakeword (linux/arm64, static) =="
( cd "$ROOT/build/station-wakeword" && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
	go build -trimpath -ldflags="-s -w" -o "$ROOT/dist/wakeword.arm64" ./cmd/wakeword )

echo "== done =="
ls -la "$ROOT/dist/"
# Sanity: both must be aarch64.
file "$ROOT/dist/quasar-bridge.arm64" "$ROOT/dist/wakeword.arm64" 2>/dev/null | grep -q aarch64 \
	&& echo "OK: aarch64 binaries ready in dist/" || echo "WARNING: binaries are not aarch64"
