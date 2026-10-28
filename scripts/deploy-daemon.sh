#!/bin/sh
# Deploy the patched wake-word daemon to the Station and wire it to the bridge:
#  - upload the arm64 binary and the init script
#  - copy QUASAR_CONTROL_TOKEN from the bridge's runtime.env into the daemon env
#  - install the init script on the (remounted) rootfs and start the daemon
# Run AFTER scripts/deploy-bridge.sh (it reads the token the bridge stored).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck disable=SC1091
. "$HERE/lib.sh"

BIN="$ROOT/${WAKEWORD_BIN:-dist/wakeword.arm64}"
INIT="$ROOT/${WAKEWORD_INIT:-config/S97wakeword}"
[ -f "$BIN" ] || { echo "ERROR: $BIN missing — run scripts/build.sh first"; exit 1; }
[ -f "$INIT" ] || { echo "ERROR: $INIT missing"; exit 1; }

echo "== 1/5 upload binary + init script =="
station_scp "$BIN" "$WAKEWORD_DIR/wakeword.new"
station_scp "$INIT" "$WAKEWORD_DIR/S97wakeword.new"

echo "== 2/5 copy control token from the bridge into the daemon env (never printed) =="
station 'src="'"$BRIDGE_STATE"'/runtime.env"; dst="'"$WAKEWORD_DIR"'/wakeword.env";
	t=$(sed -n "s/^QUASAR_CONTROL_TOKEN=//p" "$src" 2>/dev/null);
	[ -n "$t" ] || { echo "ERROR: no QUASAR_CONTROL_TOKEN in $src — deploy the bridge first"; exit 1; }
	umask 077; printf "QUASAR_CONTROL_TOKEN=%s\n" "$t" > "$dst"; chmod 600 "$dst"; echo "   wrote $dst (600)"'

echo "== 3/5 stop daemon + install binary =="
station '/etc/init.d/S97wakeword stop >/dev/null 2>&1 || true;
	chmod 755 "'"$WAKEWORD_DIR"'/wakeword.new"; mv -f "'"$WAKEWORD_DIR"'/wakeword.new" "'"$WAKEWORD_DIR"'/wakeword"; echo "   installed"'

echo "== 4/5 install init script on rootfs + start =="
station 'mount -o remount,rw /;
	chmod 755 "'"$WAKEWORD_DIR"'/S97wakeword.new";
	cp -f "'"$WAKEWORD_DIR"'/S97wakeword.new" /etc/init.d/S97wakeword;
	cp -f "'"$WAKEWORD_DIR"'/S97wakeword.new" "'"$WAKEWORD_DIR"'/S97wakeword"; rm -f "'"$WAKEWORD_DIR"'/S97wakeword.new";
	sync; mount -o remount,ro / 2>/dev/null || true;
	/etc/init.d/S97wakeword start; sleep 3'

echo "== 5/5 verify =="
station 'if [ -f /tmp/wakeword.pid ] && kill -0 "$(cat /tmp/wakeword.pid)" 2>/dev/null; then echo "   RUNNING pid=$(cat /tmp/wakeword.pid)"; else echo "   NOT RUNNING"; fi;
	printf "   claims: "; if tail -40 /tmp/wakeword.log 2>/dev/null | grep -q "claims disabled"; then echo "DISABLED (token missing)"; else echo "enabled"; fi;
	tail -5 /tmp/wakeword.log 2>/dev/null | sed "s/^/     /"'
echo "DONE: say your wake word, then a question. See README for behavior."
