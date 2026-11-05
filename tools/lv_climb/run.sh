#!/bin/sh
# Headless climb check (builder_climb.lua): on a throwaway flat world, a villager climbs a
# column of scaffolding it places as it goes, stays at the top, is saved and made again up
# there (as an unloaded mapblock would), then comes down taking the column with it. It passes
# when the villager never falls or loses health and the column is gone at the end.
#
#   tools/lv_climb/run.sh [--levels N] [--hold SECONDS] [--mod-dir PATH]
#
# living_villages comes from the checkout this script is in, or --mod-dir. Other mods come
# from the user mods directory.
#
# Environment: LUANTI (server binary), LUANTI_USER (user directory holding mods/; found
# through git by default), LV_CLIMB_WORK (scratch directory, default
# $TMPDIR/lv_climb/<checkout>), LV_CLIMB_PORT (first port to try).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../.." && pwd)
. "$here/../probe_common.sh"
mods_dir=$(lv_user_dir)/mods
luanti=${LUANTI:-/Applications/luanti.app/Contents/MacOS/luanti}

levels=12
hold=30
mod_dir=$repo_root
while [ $# -gt 0 ]; do
	case $1 in
		--levels) levels=$2; shift 2 ;;
		--hold) hold=$2; shift 2 ;;
		--mod-dir) mod_dir=$2; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

work=${LV_CLIMB_WORK:-${TMPDIR:-/tmp}/lv_climb/$(basename "$repo_root")}
world=$work/world
rm -rf "$world"
mkdir -p "$world/worldmods"
lv_stage_mod "$mod_dir" "$world/worldmods/living_villages"
cp -R "$here/mod/lv_climb" "$world/worldmods/lv_climb"
if [ ! -d "$mods_dir/mcl_decor" ]; then
	echo "living_villages needs mcl_decor in $mods_dir" >&2
	exit 1
fi
cat > "$world/world.mt" << WORLD
gameid = mineclone2
backend = sqlite3
player_backend = files
auth_backend = files
load_mod_mcl_decor = true
WORLD
cat > "$work/conf" << CONF
mg_name = flat
fixed_map_seed = 7
enable_damage = true
only_peaceful_mobs = true
server_announce = false
time_speed = 0
lv_climb_levels = $levels
lv_climb_hold = $hold
CONF

port=$(lv_claim_port "${LV_CLIMB_PORT:-30960}" "$work/../ports")
trap 'lv_release_port "$port" "$work/../ports"' EXIT
limit=$((levels * 3 + hold * 2 + 120))
LUANTI_USER_PATH=$(dirname "$mods_dir") timeout "$limit" "$luanti" --server --world "$world" --gameid mineclone2 \
	--config "$work/conf" --port "$port" > "$work/server.log" 2>&1 || true
cat "$world/climb.log" 2> /dev/null || { echo "no result; see $work/server.log" >&2; exit 1; }
grep -q '^PASS' "$world/climb.log"
