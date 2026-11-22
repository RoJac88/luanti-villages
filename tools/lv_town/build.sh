#!/bin/sh
# Builds the standard test village (tools/lv_town/README.md) on a fresh flat world, headless,
# and packs it as a template for tools/lv_world/lvw.sh new.
#
#   tools/lv_town/build.sh [--seed N] [--ref REF] [--push]
#
# --seed  the world seed and the village's PseudoRandom (default 1)
# --ref   the living_villages code that builds it (default origin/main)
# --push  copy the template to the thinkpad (~/LVTown-<seed>.tar)
#
# Environment: LUANTI (server binary, default /usr/bin/luanti), LUANTI_USER (user
# directory holding mods/ with mcl_decor and games/mineclone2; found through git by
# default), LV_TOWN_WORK (scratch directory), LV_TOWN_PORT (first port to try).
# Prints the census and leaves the template in $LV_TOWN_WORK/LVTown-<seed>.tar.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../.." && pwd)
. "$here/../probe_common.sh"
mods_dir=$(lv_user_dir)/mods
luanti=${LUANTI:-/usr/bin/luanti}

seed=1
ref=origin/main
push=false
while [ $# -gt 0 ]; do
	case $1 in
		--seed) seed=$2; shift 2 ;;
		--ref) ref=$2; shift 2 ;;
		--push) push=true; shift ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

work=${LV_TOWN_WORK:-${TMPDIR:-/tmp}/lv_town}
name=LVTown-$seed
world=$work/$name
rm -rf "$world"
mkdir -p "$world/worldmods/living_villages"
git -C "$repo_root" archive "$ref" | tar -x -C "$world/worldmods/living_villages"
git -C "$repo_root" log --oneline -1 "$ref" > "$world/built_with"
cp -R "$here/mod/lv_town" "$world/worldmods/lv_town"
if [ ! -d "$mods_dir/mcl_decor" ]; then
	echo "living_villages needs mcl_decor in $mods_dir" >&2
	exit 1
fi
cat > "$world/world.mt" << WORLD
gameid = mineclone2
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
load_mod_mcl_decor = true
WORLD
cat > "$work/conf" << CONF
mg_name = flat
fixed_map_seed = $seed
mg_flags = nocaves,nodungeons,nodecorations
mgflat_spflags = nolakes,nohills,nocaverns
enable_damage = false
only_peaceful_mobs = true
server_announce = false
max_forceloaded_blocks = 4000
lv_town_setup = true
lv_town_seed = $seed
CONF

port=$(lv_claim_port "${LV_TOWN_PORT:-30970}" "$work/ports")
trap 'lv_release_port "$port" "$work/ports"' EXIT
echo "building $name with $(cat "$world/built_with") on port $port (about 10 minutes)"
LUANTI_USER_PATH=$(dirname "$mods_dir") timeout 1200 "$luanti" --server --world "$world" --gameid mineclone2 \
	--config "$work/conf" --port "$port" > "$work/server.log" 2>&1 || true
grep '\[lv_town\]' "$work/server.log" | sed 's/^.*\[lv_town\] //'
grep -E 'ERROR|stack traceback' "$work/server.log" | head -5 || true
[ -f "$world/setup.done" ] || { echo "setup did not finish; see $work/server.log" >&2; exit 1; }
# The template: the world without the code under test, which lvw.sh start puts in.
rm -rf "$world/worldmods/living_villages" "$world/force_loaded.txt"
(cd "$work" && tar -cf "$name.tar" "$name")
echo "template $work/$name.tar"
if $push; then
	scp -q "$work/$name.tar" "${LV_HOST:-rodri@thinkpad-win11}:" && echo "pushed ~/$name.tar"
fi
