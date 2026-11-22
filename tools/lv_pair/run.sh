#!/bin/sh
# Starts an A/B pair on the thinkpad: two fresh copies of one template world, each on its
# own code, side by side (README.md).
#
#   tools/lv_pair/run.sh <name> <refA> <refB> [--template LVTown-1] [--ports 30124,30125]
#
# Worlds <name>-a and <name>-b are made from ~/<template>.tar (tools/lv_town/build.sh
# --push), replacing older ones of those names. Port 30123 is left to ColonyFood.
# The weather never changes (mcl_doWeatherCycle): a thunderstorm sends every villager to
# bed at any hour, and the two copies draw their weather apart. In pair e3 (2026-11-22)
# one copy slept through a storm of 1.3 game days, ate 4 meal points in a day and served no
# dinner, while the other had rain.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
host=${LV_HOST:-rodri@thinkpad-win11}
[ $# -ge 3 ] || { sed -n '2,9p' "$0"; exit 2; }
name=$1; refa=$2; refb=$3; shift 3
template=LVTown-1
ports=30124,30125
while [ $# -gt 0 ]; do
	case $1 in
		--template) template=$2; shift 2 ;;
		--ports) ports=$2; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done
porta=${ports%,*}; portb=${ports#*,}
lvw() { ssh "$host" "& \"C:\\Program Files\\Git\\bin\\bash.exe\" -l -c \"~/lvw.sh $*\"" 2>&1 | grep -v '^\*\*' || true; }
"$here/../lv_world/push-mod.sh" "$refa" "$name-a"
"$here/../lv_world/push-mod.sh" "$refb" "$name-b"
for side in a b; do
	lvw stop "$name-$side" > /dev/null
	lvw new "$name-$side" "~/$template.tar"
done
lvw start "$name-a" "$porta" "$name-a" mcl_doWeatherCycle=false
lvw start "$name-b" "$portb" "$name-b" mcl_doWeatherCycle=false
echo "compare with: tools/lv_pair/compare.sh $name"
