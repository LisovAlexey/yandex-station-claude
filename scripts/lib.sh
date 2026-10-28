# Shared helpers, sourced by the deploy scripts. The caller sets ROOT first.
# Not meant to be run directly.
: "${ROOT:?lib.sh: ROOT must be set by the caller}"

if [ -f "$ROOT/config.env" ]; then
	# shellcheck disable=SC1091
	. "$ROOT/config.env"
else
	echo "ERROR: $ROOT/config.env not found. Copy config.env.example and edit it." >&2
	exit 1
fi

: "${STATION_HOST:?set STATION_HOST in config.env}"
: "${STATION_SSH_PORT:=2222}"
: "${BRIDGE_DIR:=/data/quazar/yam/data/plugins/quasar-bridge}"
: "${BRIDGE_STATE:=/data/opt/quasar-bridge}"
: "${WAKEWORD_DIR:=/data/wakeword}"

# Run a command on the Station over SSH.
station() { ssh -p "$STATION_SSH_PORT" "$STATION_HOST" "$@"; }

# Copy a local file to the Station: station_scp <local> <remote-path>
station_scp() { scp -P "$STATION_SSH_PORT" "$1" "$STATION_HOST:$2"; }
