#!/bin/sh
# Stops both worlds of a pair: tools/lv_pair/stop.sh <name>
set -eu
host=${LV_HOST:-rodri@thinkpad-win11}
for side in a b; do
	ssh "$host" "& \"C:\\Program Files\\Git\\bin\\bash.exe\" -l -c \"~/lvw.sh stop $1-$side\"" 2>&1 | grep -v '^\*\*' || true
done
