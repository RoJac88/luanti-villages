#!/bin/sh
# An A/B pair on this machine instead of the thinkpad (run.sh): the same template, code
# from git refs, lv_keep from this checkout, no weather. One pair per host at a time: two
# servers are what the hardware runs side by side.
#
#   tools/lv_pair/local.sh run <name> <refA> <refB> [--template FILE] [--ports 30124,30125]
#   tools/lv_pair/local.sh stop <name>
#   tools/lv_pair/local.sh compare <name> [--from DAY]
#   tools/lv_pair/local.sh status
#
# Worlds live in $LV_PAIR_LOCAL (default ~/.cache/lv_pair)/<name>/{a,b}, logs in each
# world's server.log. The template defaults to ~/.cache/lv_pair/LVTown-1.tar; copy the
# thinkpad's (scp rodri@thinkpad-win11:LVTown-1.tar ~/.cache/lv_pair/) so both hosts run
# the same village.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
base=${LV_PAIR_LOCAL:-$HOME/.cache/lv_pair}
luanti=${LUANTI:-luanti}
cmd=${1:-}; [ $# -gt 0 ] && shift

running() { pid=$(cat "$1/server.pid" 2>/dev/null) && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; }

stop_world() {
	w=$1
	running "$w" || { echo "$(basename "$(dirname "$w")")-$(basename "$w") is not running"; return 0; }
	# lv_keep shuts the server down cleanly, saving the world, when this file appears.
	touch "$w/world/lv_keep.stop"
	for _ in $(seq 1 60); do
		running "$w" || { rm -f "$w/server.pid"; echo "stopped $(basename "$(dirname "$w")")-$(basename "$w")"; return 0; }
		sleep 2
	done
	echo "still running after 120 s: kill $(cat "$w/server.pid")"
}

start_world() {
	w=$1; ref=$2; port=$3
	world=$w/world
	rm -rf "$world/worldmods/living_villages" "$world/worldmods/lv_keep" "$world/lv_keep.stop"
	mkdir -p "$world/worldmods/living_villages"
	git -C "$root" archive "$ref" | tar -x -C "$world/worldmods/living_villages"
	git -C "$root" log --oneline -1 "$ref" > "$world/worldmods/living_villages/.lvw_version"
	cp -R "$root/tools/lv_world/lv_keep" "$world/worldmods/"
	{
		echo "name = rskj"
		echo "max_forceloaded_blocks = 4000"
		echo "server_announce = false"
		echo "enable_damage = false"
		echo "creative_mode = true"
		echo "mcl_doWeatherCycle = false"
		[ -f "$world/lvw.conf" ] && cat "$world/lvw.conf"
	} > "$w/server.conf"
	setsid "$luanti" --server --world "$world" --gameid mineclone2 --config "$w/server.conf" \
		--port "$port" --logfile "$w/server.log" > /dev/null 2>&1 < /dev/null &
	echo $! > "$w/server.pid"
	sleep 8
	if running "$w"; then
		echo "started $(basename "$(dirname "$w")")-$(basename "$w") on port $port, log $w/server.log (code $(cat "$world/worldmods/living_villages/.lvw_version"))"
	else
		echo "server did not start"; tail -5 "$w/server.log"; exit 1
	fi
}

case "$cmd" in
run)
	[ $# -ge 3 ] || { sed -n '5,9p' "$0"; exit 2; }
	name=$1; refa=$2; refb=$3; shift 3
	template=$base/LVTown-1.tar; ports=30124,30125
	while [ $# -gt 0 ]; do
		case $1 in
			--template) template=$2; shift 2 ;;
			--ports) ports=$2; shift 2 ;;
			*) echo "unknown option $1" >&2; exit 2 ;;
		esac
	done
	[ -f "$template" ] || { echo "no template $template"; exit 1; }
	for d in "$base"/*/a "$base"/*/b; do
		[ -d "$d" ] && running "$d" && case $d in "$base/$name/"*) ;; *) echo "a pair already runs here: $d (one per host)"; exit 1 ;; esac
	done
	for side in a b; do
		w=$base/$name/$side
		stop_world "$w" > /dev/null
		rm -rf "$w"; mkdir -p "$w"
		t=$(mktemp -d)
		tar -xf "$template" -C "$t"
		mv "$(ls -d "$t"/*/ | head -1)" "$w/world"; rm -rf "$t"
		sed -i '/load_mod_living_villages/d' "$w/world/world.mt"
		rm -f "$w/world/force_loaded.txt"
	done
	start_world "$base/$name/a" "$refa" "${ports%,*}"
	start_world "$base/$name/b" "$refb" "${ports#*,}"
	echo "compare with: tools/lv_pair/local.sh compare $name" ;;
stop)
	stop_world "$base/$1/a"; stop_world "$base/$1/b" ;;
compare)
	name=$1; shift
	"$here/compare.sh" --logs "$base/$name/a/server.log" "$base/$name/b/server.log" "$@" ;;
status)
	for d in "$base"/*/a "$base"/*/b; do
		[ -d "$d" ] || continue
		n="$(basename "$(dirname "$d")")-$(basename "$d")"
		if running "$d"; then echo "$n running (pid $(cat "$d/server.pid"), code $(cat "$d/world/worldmods/living_villages/.lvw_version"))"; else echo "$n"; fi
	done ;;
*) sed -n '2,13p' "$0"; exit 2 ;;
esac
