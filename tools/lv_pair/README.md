# A/B pairs on the standard test village

ColonyFood ran for more than 1,000 game days across about 40 versions of the code. By then it
showed problems a new village never would, and it could only test one version at a time. These
tools test a branch the way a new village meets it. Two copies of one freshly built village run
side by side on the thinkpad, each on its own code, and their numbers are compared day by day.

Three parts:

- **`tools/lv_town/`** builds the standard village once, headless on this machine, as a
  template world.
- **`tools/lv_world/`** runs persistent worlds on the thinkpad. It used to live in
  `~/.cache/lv_probe_keep/lv_world`. It holds `lvw.sh`, `push-mod.sh` and the `lv_keep`
  world mod, which keeps a village running with no player on and logs a daily line per
  villager.
- **`tools/lv_pair/`** starts a pair, stops it, and compares the two runs.

## The standard village

`tools/lv_town/build.sh` makes a flat world (`mg_name = flat`, no caves, dungeons, lakes,
hills or decorations) and runs the `lv_town` world mod's setup. The setup:

1. digs a pond near spawn;
2. builds a village at spawn with `living_villages`' own planner, buildings, stash chests and
   staffing, as a generated village is built;
3. gives every trade that has nobody a job block on open ground: farmer, fisherman, fletcher,
   shepherd, librarian, cartographer, armorer, butcher, weapon smith, tool smith, cleric, mason,
   leatherworker, keeper, Builder, woodcutter and alchemist. It adds tower houses if too few
   villagers are out of work, and leaves 2 out of work as labourers;
4. adds two chickens by the butcher's smoker, an oak grove, sugar cane along a channel,
   poppies and the quarry (a cobblestone generator), and puts a chest by any bed that has no
   stash;
5. writes `census.json`, plus `lvw.conf` with `lv_keep`'s centre and the spawn point, then
   shuts down.

The build fails, and says why, if any trade is missing, if a villager has no stash, if
there are fewer than two chickens, or if there isn't exactly one bell (one village). The
`lv_town` mod stays in the template, and it declines every village VoxeLibre would
generate, so the test village is the only one however far the world grows. The cows and
sheep come from the leatherworker's herd and the shepherd's flock, which seed themselves.

```sh
tools/lv_town/build.sh --seed 1 --push   # about 10 minutes; prints the census
```

`--ref` picks the `living_villages` code the village is built with (default `origin/main`).
The template keeps that version in `built_with`, and the code under test replaces it when a
run starts. Rebuild the template only when the village itself should change: every pair run
on the same template starts from the same world.

## Running a pair

```sh
tools/lv_pair/run.sh food main feature/my-branch   # worlds food-a (main) and food-b (branch)
tools/lv_pair/compare.sh food                     # one row per game day, then the means
tools/lv_pair/stop.sh food
```

- `run.sh` pushes each ref as its own tarball (`push-mod.sh <ref> <tag>`). Nothing is
  checked out, so a branch only needs to be committed.
- Both worlds start with the weather cycle off (`mcl_doWeatherCycle = false`), so they stay
  clear. A thunderstorm sends every villager to bed at any hour, and two copies draw their
  weather apart: in pair e3 one copy slept through a storm of 1.3 game days and served no
  dinner, while the other had rain.
- It makes both worlds fresh from `~/LVTown-1.tar` (`--template`) and starts them on ports
  30124 and 30125 (`--ports`). Port 30123 stays ColonyFood's.
- Both worlds run until stopped. `lv_keep` skips nights, so a game day takes about 11.5
  minutes.
- Players can join either world on its port.

`compare.sh <name>` fetches both current logs. `--logs A B` compares two logs you already
have, and `--from DAY` drops the days before DAY. For each side the columns are:

| Column | Meaning |
|--------|---------|
| din/dem | Diners at the tavern that evening, out of the keeper's demand |
| $ | The posted dinner price |
| hun | Hungry plus starving adults at the work bell, out of all adults |
| money, top | All villagers' emeralds, and the share held by the richest three |
| trd, em | Trades (face to face and from stashes), and the emeralds they moved |
| dsh | Dishes the butcher cooked |
| kb | Lots the keeper bought |
| fai | Trade trips given up |
| x | Deaths |

The means are taken over the days both sides finished.

### A pair on this machine

`local.sh` runs a pair here instead, for a second pair alongside the thinkpad's. Run one
pair per host at a time: two servers are what each machine runs side by side.

```sh
scp rodri@thinkpad-win11:LVTown-1.tar ~/.cache/lv_pair/   # the same village as the thinkpad
tools/lv_pair/local.sh run fuel experiment/a experiment/b
tools/lv_pair/local.sh compare fuel
tools/lv_pair/local.sh stop fuel
```

It needs `luanti` with the mineclone2 game and mcl_decor among the user mods. Worlds and
their `server.log` are kept in `~/.cache/lv_pair/<name>/{a,b}` (`LV_PAIR_LOCAL`).

## How much is noise

Two copies of the same world on the same code still drift apart, because timing differs from
run to run. Before trusting an A/B difference, run an A/A pair (`run.sh aa main main`) for
about 15 game days and compare it. Any gap between its two columns is noise, and an A/B
difference no bigger than that shows nothing.

A/A noise floor, measured on pair `aa` (main 5c7f5c5 on both copies of LVTown-1, 24 game
days, 2026-11-22). Means per day:

| | diners | demand | price | hungry | trades | emeralds | dishes | keeper buys | fails | dead |
|---|---|---|---|---|---|---|---|---|---|---|
| A | 7.2 | 11.4 | 31.67 | 6.4 | 7.3 | 268.7 | 2.7 | 0.3 | 8.7 | 1 |
| B | 8.5 | 11.3 | 22.79 | 4.8 | 6.8 | 258.8 | 3.3 | 0.2 | 4.9 | 2 |

Read an A/B difference against these gaps:
- Diners, demand, trades, emeralds and dishes held within about 20% over 24 days.
- The dinner price drifted by a third, and failed trips nearly doubled, so neither shows
  much over a short run.
- Hungry adults differed by 1.6.
- The deaths were the same labourer smothered in its own grove tree, in both copies.

Over the first 5 days the two copies differ more: one day's diners differed by 7.

## lvw.sh

Each world records the pid of its own server, so several can run at once:

```sh
~/lvw.sh new <name> ~/LVTown-1.tar      # a fresh world from a template
~/lvw.sh start <name> [port] [tag]      # ~/lvmod-<tag>.tar, or ~/lvmod.tar for tag main
~/lvw.sh stop <name>
~/lvw.sh status                         # every world, and which are running
~/lvw.sh path <name>                    # the current log, for scp
```

`push-mod.sh [ref] [tag]` packs any ref, with this checkout's `lv_keep`. With no arguments it
packs `HEAD` as `main`, which is what `lvw.sh start ColonyFood` has always used.
