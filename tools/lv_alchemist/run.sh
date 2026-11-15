#!/bin/sh
# Headless alchemist check (alchemist.lua, ticket 20): on a throwaway flat world, a villager
# out of work with a bed takes up an alchemist's stand placed near it, walks to it in the
# work stage and stays there through tavern time, keeps the role when saved and made again
# (as an unloaded mapblock would), and loses it when the stand is dug. Given cobble, it
# makes iron nuggets at the stand (ticket 20c).
#
#   tools/lv_alchemist/run.sh [--mod-dir PATH]
#
# living_villages comes from the checkout this script is in, or --mod-dir. Other mods come
# from the user mods directory.
#
# Environment: LUANTI (server binary), LUANTI_USER (user directory holding mods/; found
# through git by default), LV_ALCHEMIST_WORK (scratch directory, default
# $TMPDIR/lv_alchemist/<checkout>), LV_ALCHEMIST_PORT (first port to try).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../.." && pwd)
. "$here/../probe_common.sh"
mods_dir=$(lv_user_dir)/mods
luanti=${LUANTI:-/Applications/luanti.app/Contents/MacOS/luanti}

mod_dir=$repo_root
while [ $# -gt 0 ]; do
	case $1 in
		--mod-dir) mod_dir=$2; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

work=${LV_ALCHEMIST_WORK:-${TMPDIR:-/tmp}/lv_alchemist/$(basename "$repo_root")}
world=$work/world
rm -rf "$world"
mkdir -p "$world/worldmods"
lv_stage_mod "$mod_dir" "$world/worldmods/living_villages"
cp -R "$here/mod/lv_alchemist" "$world/worldmods/lv_alchemist"
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
CONF

port=$(lv_claim_port "${LV_ALCHEMIST_PORT:-30970}" "$work/../ports")
trap 'lv_release_port "$port" "$work/../ports"' EXIT
LUANTI_USER_PATH=$(dirname "$mods_dir") timeout 400 "$luanti" --server --world "$world" --gameid mineclone2 \
	--config "$work/conf" --port "$port" > "$work/server.log" 2>&1 || true
cat "$world/alchemist.log" 2> /dev/null || { echo "no result; see $work/server.log" >&2; exit 1; }
grep -q '^PASS' "$world/alchemist.log"
