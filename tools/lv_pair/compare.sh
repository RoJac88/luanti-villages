#!/bin/sh
# Puts a pair's two runs side by side, one row per game day, then the means over the days
# both reached (README.md).
#
#   tools/lv_pair/compare.sh <name> [--from DAY]   every session of both worlds (lvw.sh all)
#   tools/lv_pair/compare.sh --logs A.log B.log [--from DAY]   two logs already fetched
set -eu
here=$(cd "$(dirname "$0")" && pwd)
host=${LV_HOST:-rodri@thinkpad-win11}
from=0
if [ "${1:-}" = --logs ]; then
	a=$2; b=$3; shift 3
else
	name=$1; shift
	dir=${TMPDIR:-/tmp}/lv_pair/$name; mkdir -p "$dir"
	for side in a b; do
		path=$(ssh "$host" "& \"C:\\Program Files\\Git\\bin\\bash.exe\" -l -c \"~/lvw.sh all $name-$side\"" 2>/dev/null | tr -d '\r' | tail -1)
		scp -q "$host:$path" "$dir/$side.log"
	done
	a=$dir/a.log; b=$dir/b.log
fi
[ "${1:-}" = --from ] && from=$2
awk -v from="$from" -f "$here/compare.awk" "$a" "$b"
