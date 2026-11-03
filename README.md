# Living Villages

Living Villages gives VoxeLibre villagers daily lives. Villagers sleep in their beds, have children
when there's room, fish, keep taverns, and meet for dinner in the evening. The mod keeps
VoxeLibre's own trading, professions, and bed-ownership format, so removing it returns the
game's default villager behavior. Child villagers, bed claims, and placed furniture stay in the
world.

## Features

### Sleep and births

- Villagers lie visibly in their claimed beds at night.
- A village can have a child when a valid bed is unclaimed, as long as two nearby adults own
  beds and no nearby adult is without one. Automatic births are limited to about one every two
  game days in a local area.
- Both parents must also have been fed 12 points of food by a farmer, which they spend. **A
  village with no working farm stops growing by itself.** `living_villages_births_need_food`
  turns this off.
- Breeding with food also needs a free bed, but doesn't wait for the birth timer.
- Beds owned by players don't count. Spawn eggs and curing zombie villagers work as before.

### Farmers

A villager with a composter works its farm through the work stage:

- **Harvests and sows.** Mature wheat, potatoes, carrots and beetroot yield their real drops, which it carries. It sows from what it carries, so a farmer with no seeds plants nothing until it harvests or finds some. It avoids sowing the same crop as the plot's neighbours where it can, because that crop grows slower.
- **Tills.** With seeds and nothing left to sow, it tills beside its field, onto dirt or grass that water will keep wet, up to `living_villages_farm_max_plots` plots. A composter beside water with no field starts one. It never tills a path. The stock farm's kerb keeps its field to its bed.
- **Composts and bakes.** It adds surplus crops and seeds to its composter, takes the bone meal and spends it on the crops furthest from ripe. It bakes wheat into bread.
- **Stores.** It takes large surpluses to the nearest chest within `living_villages_farmer_chest_radius` nodes of its composter, generated or yours, and takes back seeds and food when short. It never places a chest. With none in range it only composts and hands food out, and a full farmer leaves crops standing. `living_villages_farmer_chest_withdraw` makes chests deposit-only. Trapped, ender and protected chests are left alone.
- **Feeds the village.** It hands food directly to villagers near its farm. Bread is worth 4 points and a crop 1, and a villager wants 12. Food heals, and a fed child grows faster.

A farmer that dies drops what it carries.

### Who takes which job

An unemployed villager takes a free composter it can reach ahead of any other job, including a
tavern or a pulpit, and looks for one up to 96 nodes away (`living_villages_farm_job_radius`), where
other jobs are looked for within 48. If it can't reach any free composter it can take another job,
and tries the composters again five minutes later if it's still unemployed.

### Fishermen

- A villager becomes a fisherman by claiming a barrel, like any other workstation. Breaking the
  barrel of a fisherman nobody has traded with makes it unemployed again. One that has traded keeps
  its profession and looks for another barrel, and only fishes once it has one.
- During work hours it walks to a spot at the water's edge within 32 nodes of its barrel and casts,
  waits, and reels in. Fishing produces no items. Instead it restocks the fisherman's locked trades
  within its current tier. With no water in range it works at the barrel, like any other villager.

### Getting around

For trips to a bed, workstation, farm plot, or fishing spot, villagers first use VoxeLibre's
normal pathfinding. If that fails, they fall back to a limited route planner that can use
ordinary stairs and wooden doors. Iron doors still block them.

### Churches

- **Pulpit:** `living_villages:pulpit` is a lectern with a purple texture that no profession
  claims as a jobsite. Craft one from a lectern and a purple carpet. A pulpit marks a church, so
  a player-built church works too. It is the mod's only node: if you remove the mod, placed
  pulpits become unknown nodes.
- **Furniture:** newly generated churches lose the brewing stand, get a pulpit beside the altar on the
  congregation's left, and get chairs in place of the stair pews, all facing the altar. Churches that already exist aren't
  refurnished.

### Taverns and dinner

- **Furniture:** newly generated taverns get two tables with plates and chairs. The furniture
  is added to the installed VoxeLibre version's own tavern layout when the tavern generates.
  Taverns that already exist aren't refurnished.
- **Keepers:** an unemployed adult that claims a free jukebox becomes a tavern keeper. The
  jukebox can be a tavern's or one a player placed. A keeper wears a brown apron and sells
  bread, baked potatoes, cooked fish, mushroom stew, and pumpkin pie through the ordinary
  trade window. More of its menu unlocks as players trade with it. A keeper opens the tavern at
  14:00, stays until 18:30, and is the last villager in the village to go to sleep.
  - VoxeLibre can't register new professions, so a keeper is a butcher underneath.
  - A keeper that loses its jukebox after trading keeps its menu and looks for another
    jukebox, not a smoker.
- **Evening visit:** from 15:30, every adult walks to the nearest tavern within 48 nodes of its
  bed and stays until 17:30. An adult that hasn't arrived by 17:00 goes home instead.
  - If a tavern has no keeper, the first villager to reach it takes the job and leaves its old
    one, unless a player has traded with it or it's a farmer.
- **Seating:** guests each take a free chair that faces a table. This works in any tavern,
  including ones players built. Guests never take a chair a player is sitting in, and they get
  up if a player takes their chair. When no seat is free, a guest stands inside.
- **Dinner:** while the keeper is at its jukebox, it serves each seated guest one meal from its
  menu each evening. The meal appears on the plate at the guest's table, and the plate empties
  as the guest eats. The meal is only for show and can't be taken. A keeper never serves on a
  plate that holds a player's item, and a tavern with no keeper on duty serves no meals.

## Requirements

- [VoxeLibre](https://content.luanti.org/packages/wuzzy/mineclone2/) 0.92.3. Other versions
  may work but haven't been tested.
- These VoxeLibre mods: `mobs_mc`, `mcl_beds`, `mcl_villages`, `mcl_itemframes`, `mcl_lectern`,
  `mcl_wool`, `mcl_farming`, `mcl_composters`, `mcl_bone_meal`, and `mcl_chests`.
- [`mcl_decor`](https://content.luanti.org/packages/EmoryNB/mcl_decor/), which is a separate mod,
  not part of VoxeLibre. Install it from ContentDB.
- Optional: `doc_identifier` (the Lookup Tool) and `mcl_fishing`.

## Installation

Put this repository in a directory named `living_villages` inside Luanti's `mods` directory, or
inside a world's `worldmods` directory. Then enable it for your world.

## Admin and testing tools

- **Inspecting villagers:** players with the `server` or `debug` privilege can use VoxeLibre's
  Lookup Tool on a villager to see its AI, bed, workstation, path, fishing, tavern, meal, and
  birth-timing state. Using the tool on a bed or workstation shows which villager owns it. The
  tool works normally on everything else.
- **`/living_villages_goto`** (requires `teleport`): teleports you above the nearest tavern
  that has generated in this world. If no tavern is known yet, it goes to the nearest untried
  spot where VoxeLibre will try to generate a village, predicted from the world seed. Once the
  village has generated, run the command again to reach its tavern, or to move on to the next
  site.
  - `/living_villages_goto any` goes to the nearest known village.
  - `/living_villages_goto new` skips known taverns and tries another site.
  - Each village is logged to `debug.txt` as it generates.
- [`docs/navigation-scenarios.md`](docs/navigation-scenarios.md) has repeatable in-game test
  scenarios for pathfinding and fishing.

## Development

The tests are plain Lua 5.1 scripts that stub the engine, and CI runs them on every push:

```sh
for t in tests/*.lua; do lua5.1 "$t"; done
```

[`AGENTS.md`](AGENTS.md) has a map of the code and the project's conventions.

## License

The code and bundled media are distributed under GPL-3.0; see [`LICENSE`](LICENSE).
Upstream media notices and credits are retained in [`LICENSE-media.md`](LICENSE-media.md).
The sleeping position, bed
occupancy, pose, and wake-up behavior are adapted from Mineclonia's `mobs_mc/villager.lua`.
The villager model and textures come from Mineclonia, and the pulpit texture is a recolored
VoxeLibre texture.
# Market days

On holidays, adult villagers gather around the village bell after church. Eligible
traders open a small stall with two representative profession goods; players can
trade with them as usual. Other villagers wander and converse around the market.
Sellers pack their displays before the evening tavern visit. Stalls use ordinary
tables and invisible item frames, so normal protection, digging, and theft behavior
still applies.
