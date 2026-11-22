#!/bin/sh
# Persistent test worlds on the thinkpad (Git Bash). Worlds live in $ROOT/<name> and are
# never wiped; the mod code in each world's worldmods is replaced from a tarball on start
# (push-mod.sh). Several worlds can run at once, each on its own port.
#   lvw.sh start <name> [port] [tag] [conf lines...]
#                             refresh the mod from ~/lvmod-<tag>.tar (~/lvmod.tar for tag
#                             main, the default) and start the server detached on port
#                             (default 30123)
#   lvw.sh stop <name>        clean shutdown (saves the world)
#   lvw.sh status             running servers and worlds
#   lvw.sh log <name> [from-line]   the current session's log from a line
#   lvw.sh import <name> <world.tar>   a world tarred with its folder named <name>
#   lvw.sh new <name> <template.tar>   a fresh world from a template (lv_town), any
#                             folder name inside; replaces an old world of that name
#   lvw.sh path <name>        the current log's Windows path, for scp
#   lvw.sh all <name>         every session's log joined in logs/all.txt; prints its path
ROOT=/c/Users/rodri/lv_probe/worlds
LUANTI_EXE='C:\Users\rodri\AppData\Local\luanti\5.18.0\bin\luanti.exe'
mkdir -p "$ROOT"
cmd=$1; name=$2
w=$ROOT/$name
pid_of() { cat "$w/server.pid" 2>/dev/null; }
# Whether this world's server is running: its recorded pid is a live luanti.exe.
running() {
	pid=$(pid_of)
	[ -n "$pid" ] && tasklist //FI "PID eq $pid" 2>/dev/null | grep -qi luanti.exe
}
case "$cmd" in
import)
	[ -e "$w" ] && { echo "world $name already exists"; exit 1; }
	tar -xf "$3" -C "$ROOT" && sed -i '/load_mod_living_villages/d' "$w/world.mt" && rm -f "$w/force_loaded.txt"
	echo "imported $name" ;;
new)
	running && { echo "world $name is running; stop it first"; exit 1; }
	t=$(mktemp -d)
	tar -xf "$3" -C "$t" || exit 1
	src=$(ls -d "$t"/*/ | head -1)
	rm -rf "$w" && mv "$src" "$w" && rm -rf "$t"
	rm -f "$w/force_loaded.txt" "$w/server.pid"; rm -rf "$w/logs"
	echo "new world $name from $(basename "$3")" ;;
start)
	[ -d "$w" ] || { echo "no world $name"; exit 1; }
	running && { echo "world $name is already running (pid $(pid_of))"; exit 1; }
	shift 2
	port=30123; tag=main
	case ${1:-} in [0-9]*) port=$1; shift ;; esac
	case ${1:-} in ''|*=*) ;; *) tag=$1; shift ;; esac
	tarball=~/lvmod-$tag.tar
	[ "$tag" = main ] && tarball=~/lvmod.tar
	[ -f "$tarball" ] || { echo "no $tarball; run push-mod.sh <ref> $tag"; exit 1; }
	rm -rf "$w/worldmods/living_villages" "$w/worldmods/lv_keep"; mkdir -p "$w/worldmods"
	tar -xf "$tarball" -C "$w/worldmods" || exit 1
	rm -f "$w/lv_keep.stop"
	{
		echo "name = rskj"
		echo "max_forceloaded_blocks = 4000"
		echo "server_announce = false"
		echo "enable_damage = false"
		echo "creative_mode = true"
		for line in "$@"; do echo "$line"; done
		[ -f "$w/lvw.conf" ] && cat "$w/lvw.conf"
	} > "$w/server.conf"
	stamp=$(date +%Y%m%d-%H%M)
	log="$w/logs/$stamp.log"; mkdir -p "$w/logs"; echo "$log" > "$w/logs/current"
	winw=$(cygpath -w "$w"); winconf=$(cygpath -w "$w/server.conf"); winlog=$(cygpath -w "$log")
	powershell.exe -NoProfile -Command "(Start-Process -PassThru -FilePath '$LUANTI_EXE' -WindowStyle Hidden -ArgumentList '--server','--world','\"$winw\"','--gameid','mineclone2','--config','\"$winconf\"','--port','$port','--logfile','\"$winlog\"').Id" | tr -d '\r' > "$w/server.pid"
	sleep 8
	running && echo "started $name on port $port, log $log (code $(cat "$w/worldmods/living_villages/.lvw_version" 2>/dev/null))" || { echo "server did not start"; tail -5 "$log"; } ;;
stop)
	running || { echo "$name is not running"; exit 0; }
	touch "$w/lv_keep.stop"
	for i in $(seq 1 60); do running || { echo "stopped $name"; rm -f "$w/server.pid"; exit 0; }; sleep 2; done
	echo "still running after 120 s" ;;
status)
	for d in "$ROOT"/*/; do
		name=$(basename "$d"); w=$ROOT/$name
		if running; then
			echo "$name running (pid $(pid_of), code $(cat "$w/worldmods/living_villages/.lvw_version" 2>/dev/null))"
		else
			echo "$name"
		fi
	done ;;
log)
	f=$(cat "$w/logs/current"); tail -n +"${3:-1}" "$f"; echo "count $(($(wc -l < "$f") + 1))" ;;
path)
	sed 's#^/c/#C:/#' "$w/logs/current" ;;
all)
	cat "$w"/logs/2*.log > "$w/logs/all.txt"; echo "$w/logs/all.txt" | sed 's#^/c/#C:/#' ;;
*) sed -n '2,16p' "$0" ;;
esac
