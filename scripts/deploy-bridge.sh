#!/bin/sh
# Deploy the patched quasar-bridge to the Station:
#  - upload the arm64 binary built by build.sh
#  - ensure a QUASAR_CONTROL_TOKEN in runtime.env (generated once, never printed)
#  - install the binary, validate config, restart via YAM, verify health
#
# Note: /data on a Station Mini is tiny. If an upload fails with "No space left",
# free room first (e.g. move negatives.bin off-device; see README) and re-run.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck disable=SC1091
. "$HERE/lib.sh"

BIN="$ROOT/${BRIDGE_BIN:-dist/quasar-bridge.arm64}"
[ -f "$BIN" ] || { echo "ERROR: $BIN missing — run scripts/build.sh first"; exit 1; }

echo "== 1/4 upload binary (.new) =="
station_scp "$BIN" "$BRIDGE_DIR/bin/quasar-bridge.new"

echo "== 2/4 ensure control token in runtime.env (generated once, never printed) =="
TOKEN=$(openssl rand -hex 32)
printf '%s' "$TOKEN" | station 'cand=$(cat); f="'"$BRIDGE_STATE"'/runtime.env";
	if [ -f "$f" ] && grep -q "^QUASAR_CONTROL_TOKEN=" "$f"; then echo "   token already present, keeping";
	else umask 077; printf "QUASAR_CONTROL_TOKEN=%s\n" "$cand" >> "$f"; chmod 600 "$f"; echo "   token added"; fi'
unset TOKEN

echo "== 3/4 install + validate + restart =="
station 'd="'"$BRIDGE_DIR"'/bin"; chmod 755 "$d/quasar-bridge.new"; mv -f "$d/quasar-bridge.new" "$d/quasar-bridge";
	sh "'"$BRIDGE_DIR"'/start.sh" -check-config && sh "'"$BRIDGE_DIR"'/control.sh" restart'

echo "== 4/4 verify =="
station 'wget -q -O - http://127.0.0.1:8443/healthz; echo'
echo "DONE: bridge deployed. Then run scripts/deploy-daemon.sh."
