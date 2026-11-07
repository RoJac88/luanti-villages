# Villager economy

Engineering design for the villager economy: villagers with needs, belongings and
the ability to trade with each other, so that a village's economy emerges from
individual villagers rather than from a village-wide script. This document records
the agreed gameplay and divides implementation into small, ordered tickets. The
fork has issues disabled, so the tickets live here (see [Tickets](#tickets)).
Numerical defaults are initial engineering choices to verify in playtesting.

Trade between villages is out of scope, but the design leaves room for it: the
peddler (ticket 12) is the first villager who carries goods from one place to
another.

## Goals

- Every villager has needs (food, its work's inputs, a few preferences), belongings
  (a pouch, a home chest, emeralds) and a sense of what things are worth to it.
- Villagers learn what others need and have spare through the gossip they already
  exchange in conversations, and trade with each other when both gain.
- Goods enter the village only through work or from players, and leave it only by
  being eaten, built with or crafted into something else. Trading moves goods and
  never creates them.
- The player has a reason to balance the professions in a village, and can see how
  well it is balanced.
- The VoxeLibre core loop is untouched: explore, gather, craft, build, and trade with
  villagers through the ordinary trade window, at vanilla stock levels.

## Non-goals

- No starvation deaths, departures or collapse. An unbalanced village stagnates.
- No village-wide store, bank or score. As with gossip, each villager knows only
  what it has seen or been told.
- No new nodes. Every site is an ordinary VoxeLibre node; the pulpit and the
  builder's bench stay the mod's only nodes.
- No change to which professions exist, how jobsites are claimed, or how traded
  villagers are locked into their profession.
- No villager takes from a player's inventory.

## Decisions

| Question | Decision |
|---|---|
| Does a villager's own emerald stock limit player trades? | No. Player trades keep vanilla's unlimited stock; the player is the economy's open edge (its "mint") |
| Do food points fall? | Yes, gradually, by about one loaf a day |
| Can villagers starve to death? | No. Hunger lowers output and stops births, never health below what it is |
| What happens while a villager is unloaded? | Its economic clock pauses: hunger, production and crafting stop together |
| Do players pay for tavern meals? | Yes, an emerald, and the meal comes out of the pantry |
| Does the farmer still give food away? | Yes to its own household, and one item to a villager at 0 points; everyone else buys |
| Do nitwits take part? | Yes, as gatherers, porters and peddlers, choosing work by what they hear pays |
| Do unemployed villagers do nitwit work? | Yes, while they wait for a jobsite. Vanilla's job claim still comes first |
| Can a village's own supply raise trade tiers? | Yes, alongside vanilla's player-trade progression, not instead of it |

## Player experience

A new village looks as it does today, except that people are carrying things.
Each villager started with a small stock suited to its profession. The farmer
sells bread to its neighbours and the keeper buys crops for the pantry. At dinner,
guests pay for their plates. When the tavern runs dry the guests still sit and
talk, but the plates stay empty, and over the next few days the villagers get
hungry.

A hungry villager works at half pace and charges the player more. Villagers that
are well fed have children; hungry villages stop growing. Nothing dies.

The nitwits and the unemployed are no longer idle. In the morning they pick up work
according to what they have heard is scarce: foraging berries and flowers, cutting
the trees of a grove they planted, working a cobblestone generator a player built,
carrying goods for a fee. When wood gets expensive more of them cut wood; when it
gets cheap they drift to other work.

Each profession needs things other villagers make, and some only players can
supply. A toolsmith with no coal or charcoal, no sticks and no cobble produces
nothing, restocks slowly and stays at a low tier. A village whose woodcutters make
charcoal, whose quarrier makes cobble and whose foragers bring sticks keeps its
smith supplied. That smith restocks reliably, climbs to master tier without the
player trading every tier up, and sells cheaply. A village short of something pays
the player well for it.

The Builder's bench gets an Economy tab: what the village makes and uses, what is
short and what is in glut, and what the idle hands are doing, as heard by the
bench's Builder. The Builder also leans its next project toward the village's worst
gap, which the player can override as today.

## Principles

1. **The player is the open edge.** Inside the village, goods are conserved: made by
   work, used up by eating, building and crafting, moved by trade. Player trades
   keep vanilla's unlimited stock and money, but what a player sells goes into the
   villager's belongings and the emeralds a player pays go to the villager.
2. **One clock, paused when unloaded.** Hunger, production and crafting all run on
   each villager's own economic clock, which advances only while the villager is
   active (see [The economic clock](#the-economic-clock)). Nothing is caught up over
   unloaded time, so a village is never found starving with full fields.
3. **Decentralized.** No village-wide state. Two villagers can disagree about a
   price, and that difference is what trade lives on.
4. **Lazy.** Work is computed from elapsed clock time when a villager acts or is
   looked at, never per tick per item.
5. **Removable.** State is in `_villages_*` entity fields and node metadata; goods
   are real items in real chests; a pouch drops on death (as the farmer's does).
   Removing the mod leaves vanilla villagers and chests full of ordinary items.

## The economic clock

`economy_clock.lua`. Each villager keeps `_villages_econ_clock`, seconds of game
time it has been economically active, and `_villages_econ_stamp`, the game time it
last advanced it. Every `STAMP_SECONDS` (10) of game time, while a player is within
mcl_mobs' active range (mcl_mobs runs `do_custom` for a suspended villager too, so the
range is asked), the clock advances by the time since the stamp. A gap of `AWAY_GAP` (120 s) or more since the last stamp (the villager was
unloaded or suspended) is not added. This is `builder_away.lua`'s stamp, used for the
opposite purpose: the Builder pays for the gap, the economy skips it.

Hunger, jobsite crafting, news freshness for a villager's own entries, and nitwit
gathering rates read the economic clock. Gossip decay and news decay for hearsay
keep using game time, since they describe the world rather than the villager's
work. `builder_away.lua` is unchanged: the Builder keeps its own paid catch-up.

Real production loops (the farmer's field, the fisherman's line, the shepherd's
shears) already only run while the villager is active, so they pause with it.

## Hunger

`food.lua` gains a falling rate: `living_villages_hunger_per_day` points per game
day of economic clock (default 4, one loaf). The cap stays 12. Points fall lazily
when read, like gossip decay.

| Points | State | Effect |
|---|---|---|
| 12 | Full | May become a parent (unchanged rule; a birth still spends 12) |
| 4 to 11 | Fed | None |
| 1 to 3 | Hungry | Production and gathering at half rate; prices to players include a hunger term; seeks food before puttering |
| 0 | Starving | No production, no health regeneration, no restocking |

A villager eats when its points are at or below `FULL - 4` and it has food, at the
home stage, from its pouch first and then its stash. Tavern dinner is the other
place it eats (see [The tavern](#the-tavern)). Eating uses `food.receive` and
`food.show_handover`'s eating sound; food never goes on the ground.

Children do not get hungry. Their household feeds them once a day, as now
(`_villages_fed_day`), and they take no part in trade.

## Possessions

`possessions.lua`, generalizing `farm_stock.lua`.

- **Pouch.** The existing saved field `_villages_farm_pouch` becomes every
  villager's pouch (its name is kept: saved state is not renamed). Capacity stays
  `POUCH_CAPACITY` (128). `farm_stock.lua`'s count/add/take functions move here and
  `farm_stock.lua` keeps its chest transfers on top of them. Drops on death, as now.
- **Emeralds.** Held in the pouch as `mcl_core:emerald`, so they drop with it and
  cost no new field.
- **Stash.** The chest nearest the villager's bed, within
  `living_villages_stash_radius` (8), claimed by `villages_owner` = the villager's
  `_id` in the chest's node metadata. A claimed chest is never another villager's
  stash. Generated chests, chests a Builder placed (`builder_block.lua`'s house
  setup) and chests a player placed are all eligible, as for the farmer (#26). The
  farmer's own chest by its composter stays its work chest; its stash is by its bed.
- **Succession.** A stash belongs to the bed. A villager who takes a bed whose
  chest names a dead or missing owner claims it and inherits what is in it, as a new
  Builder inherits a bench's project.
- **Starting stock.** On first activation (`_villages_endowed` unset) a villager
  gets a profession stock (`STARTING_STOCK`: a farmer some seeds and bread, a smith a
  few coal and ingots, everyone 3 to 6 emeralds), into its pouch. Villagers born in
  the village get emeralds only.
- **Theft.** A player who takes from a claimed stash within sight of a villager
  (gossip's witness rule: 16 nodes, line of sight) gives that villager
  `minor_negative` gossip. The owner, when it next checks its stash, records the
  loss as news ("needs" for what went missing). Nothing is locked.

## Ledger and prices

`ledger.lua`, pure: no engine calls beyond what is passed in.

**Base prices.** `trade_prices.lua` is a checked-in table of an emerald base price
per item, extracted from VoxeLibre's profession trade tables by
`tools/extract_trades/`. The tables are a `local` in `mobs_mc/villager.lua` and are
not exposed, so the tool evaluates that block with stubs, as
`tools/extract_schematics/` regenerates fixtures, and is rerun when the supported
VoxeLibre version changes. A buy offer of N items for 1 emerald prices an item at
1/N; a sell offer of E emeralds for N items at E/N. Where an item has both, the base
is their geometric mean. Items in no table (logs, cobble, saplings, sticks' sources)
get a short hand-written table in `ledger.lua`, consistent with their crafting
yield (planks at a quarter of a log, and so on).

**Targets.** Each villager has a target stock per item: what it wants to hold.

| Layer | Source |
|---|---|
| Food | Enough food points for 3 days |
| Work inputs | Its profession's recipe inputs for a day's production (see [Production](#production)); the Builder's `requires_materials` |
| Preferences | 1 or 2 items from a short list (flowers, books, a wool colour, cake), chosen by a hash of `_id`, wanted in small numbers |

**Need and surplus.** Need = target − held; surplus = held − target − reserve, where
the reserve is a quarter of the target, so a villager never sells down to nothing.

**Value.** What an item is worth to one villager: base price × urgency, where urgency
rises from 1 (no need) toward 3 as the need approaches the whole target, and falls
toward 0.5 for surplus. A villager will buy below its value and sell above it.

## Production

Every good in the village has a source in this section or comes from a player.

### Real loops

| Profession | Change |
|---|---|
| Farmer | Unchanged: crops into the pouch |
| Fisherman | Each completed cycle (`fisherman.lua`, which today only restocks) also puts a fish in the pouch, by vanilla's fishing loot odds for fish |
| Shepherd | Shears a flock sheep with wool during the work stage (`flock.lua`), adding its wool to the pouch. Wool grows back on vanilla sheep |
| Keeper | Cooks raw pantry ingredients into menu items (see [The tavern](#the-tavern)) |

### Jobsite crafting

Professions with no work loop craft at their jobsite. `production.lua` holds one
recipe list per profession: outputs from that profession's sell offers, inputs from
the real crafting recipe where there is one. A test checks every output against the
profession's trade table in `trade_prices.lua`. Over work-stage economic clock time
spent at its jobsite, a villager makes recipe outputs at
`living_villages_craft_seconds` per item (default 120), taking the inputs from its
pouch and stash. With no inputs it makes nothing. Examples, illustrative until the
recipe ticket fixes them:

| Profession | Makes | From |
|---|---|---|
| Tool smith | Stone tools | Cobble, sticks |
| Fletcher | Arrows | Sticks, flint, feathers |
| Librarian | Books | Paper, leather |
| Mason | Bricks, polished stone | Clay, stone |
| Butcher | Cooked meat | Raw meat, coal or charcoal |
| Armorer, weapon smith | Iron gear | Iron, coal or charcoal |

Charcoal counts wherever vanilla's tables ask for coal, so a village can supply its
smiths from its own woodcutters.

### Nitwit and unemployed labour

`labour.lua`. Each morning (putter stage) a nitwit, or an unemployed villager with
no jobsite in sight, chooses an activity for the day: the one with the best expected
income, which is the price it has heard for the activity's goods × the rate it can
gather them, with a small bias to yesterday's choice so villagers do not all switch
at once. With no news it picks at random among the activities it has a site for.
Vanilla's job claim always wins over this for the unemployed. `nitwit.lua`'s demotion
guard is untouched.

| Activity | Site | Rule |
|---|---|---|
| Forager | Wild plants within 32 of its bed | Sweet berry bushes (`mcl_farming:sweet_berry_bush_*`) at their last stage, apples from the ground (dropped by leaves), mushrooms, flowers, sugar cane above its bottom block. Only what grows back |
| Woodcutter | A grove near its bed | Plants saplings, fells only trees grown from saplings it planted (positions kept on the villager, `_villages_grove`, at most 8), replants each one, and smelts some logs into charcoal at a furnace in reach. Wild trees are never cut |
| Quarrier | A cobblestone generator within 32 | Mines cobble a player's water-and-lava machine makes (`mcl_core`'s "Lava cooling" ABM). Never digs terrain |
| Porter | Stashes of villagers who hire it | Carries goods for a buyer's trade trip, for a fee |
| Peddler | The village | Buys surplus below the going price and sells where it has heard of need, keeping the margin (ticket 12) |

## Market news

An extension of `gossip.lua`. A second memory, `_villages_market_news`, a list of at
most `NEWS_ENTRIES` (24) entries:

```lua
{item = "mcl_core:coal_lump", who = "<villager _id>", kind = "has" | "needs",
	count = 12, price = 0.07, home = <bed pos>, heard = <game time>, hops = 1}
```

- A villager's own top three needs and surpluses from its ledger are always
  shareable, with `hops = 0`.
- When a conversation runs its full time, `conversation.lua` already calls
  `gossip.exchange(members)`. Exchange also shares up to `NEWS_SHARE` (6) news
  entries each way, chosen by the **listener's** interest: an item the listener needs
  or has spare weighs more, fresher and fewer hops weigh more. Hearsay costs a hop.
  The listener keeps the freshest entry per (item, who, kind).
- Entries older than `NEWS_DAYS` (2) game days are forgotten. When the cap is
  reached, the least interesting entry goes.

This makes the well, the bell, the church social and the tavern the village's
market-information network. A villager who talks a lot finds trades sooner.

## Exchange between villagers

`exchange.lua`. A trade happens only when the buyer's value for the goods is above
the seller's. It settles at the midpoint, in emeralds, or in goods when the buyer is
out of emeralds and the seller needs something it has. Goods pass pouch to pouch
with `food.show_handover`'s animation. Three channels, in order:

1. **End of conversation.** After news is exchanged, each member checks the others
   for a trade it now knows of. They are standing together and loaded, so this
   needs no navigation. At most one trade per pair per conversation.
2. **Trade trips.** A villager with an urgent need (urgency above 2) and news of a
   seller walks to the seller, or to the seller's stash if the seller is not home,
   in its putter stage, through `navigation.lua`, with `far_trips.lua` covering the
   distance from home. A porter can be hired instead. The Builder buys its missing
   materials this way.
3. **Holiday market.** `market.lua` stalls show the seller's real surplus instead of
   its profession's two fixed goods, and browsers buy at stalls.

## The farmer's food

`farmer.lua`'s `hand_over` gives food only to:

- its household: villagers sharing its bed's house (the beds within the same
  building as its own) and their children, free;
- a villager at 0 points, one item free (a farmer's handout);
- the tavern pantry, sold in bulk at the pantry chest (a deposit target next to its
  own chest);
- anyone else who pays its asking price, through exchange.

## The tavern

- **Pantry.** The chests within 6 of the keeper's jukebox; the stock tavern's chest
  stands 3 behind it. The keeper fetches food for it from the farms (ticket 1);
  from ticket 4 farmers and fishermen sell into it.
- **Cooking.** The keeper turns raw pantry items into its menu items over its shift:
  bread from wheat, baked potatoes from potatoes, cooked fish from raw fish.
- **Dinner.** `meal.lua` serves a guest only when the pantry has a menu item: it
  takes the item, the guest gains its food points and pays the keeper its price in
  emeralds. Only the keeper's own household eats free. With an empty pantry the
  guest is seated and nothing is served.
- **Player meals.** `player_meals.lua` takes the meal from the pantry and charges
  the player one emerald from their inventory before serving. A player with no
  emerald, or a tavern with an empty pantry, is not served and the log says which.
- **Player trades.** The keeper's menu trades stay vanilla (unlimited). A low pantry
  raises the player's price through the demand term.

## What the player sees

**Prices.** Java's demand term, which `gossip.lua` leaves out "since neither exists
here", now exists. The ledger's urgency for an offer's item moves the first
ingredient of that trade for every player, through the same `wanted` list wrapper
reputation uses, combined with reputation in one place. A villager short of what it
buys pays more for it; one with a glut of what it sells sells cheaper. A hungry
villager adds a hunger term to what it sells.

**Restocking.** Vanilla restocks a villager's locked trades in `unlock_trades` when
it arrives at its jobsite (`mobs_mc/villager.lua`, `do_work`). A wrapper skips that
for a starving villager, and for a crafting profession whose stash and pouch hold no
recipe inputs. The fisherman's per-cycle restock is unchanged.

**Tiers.** Vanilla raises `_max_trade_tier` when a player first uses a trade at
the top tier, or with a 1 in 5 chance on a freshly restocked one. In addition, a
villager that has crafted on `living_villages_tier_supply_days` (3) separate days at
its current tier, entirely from inputs it bought from villagers or produced itself,
goes up one tier, up to 5. Both routes run; the faster one wins.

**Visibility.**

- **Economy tab** on the Builder's bench (`builder_bench_menu.lua`): goods made and
  used per day, shortages and gluts, idle hands and their activities, professions
  present against the dependency graph. It reports the bench Builder's market news
  and is labelled as what it has heard.
- **Need bubble.** A small icon of a villager's most urgent need over its head while
  a player looks at it within 8 nodes.
- **Census.** `village_census.lua`'s choice of building gains an economic weight:
  a building that houses the worst gap's jobsite counts double. The bench menu's
  choice still overrides it.
- **Inspector.** `diagnostic.lua` shows a villager's food, clock, pouch, stash,
  ledger and news.

## Profession dependencies (VoxeLibre 0.92.3)

From `mobs_mc/villager.lua`'s trade tables. "Buys" are a profession's inputs in this
design; whether the village can supply them decides how well it works without a
player.

| Profession | Buys (inputs) | Village source | Sells (outputs) |
|---|---|---|---|
| Farmer | Wheat, potato, carrot, beetroot, pumpkin, melon | Its own fields | Bread, pie, apple, cookie, cake, stew |
| Fisherman | String, coal, raw fish, raw salmon, boats | Own line; charcoal | Cooked fish, campfire, rod |
| Shepherd | Wool, dyes | Own flock; foraged flowers for dyes | Wool, carpet, beds, banners, shears |
| Fletcher | Sticks, flint, string, feathers | Woodcutter; quarrier's gravel; player | Arrows, flint, bows, crossbows |
| Librarian | Paper, books, ink sacs, writable books | Forager's sugar cane; player | Enchanted books, bookshelves, lanterns, glass, clock, compass |
| Cartographer | Paper, glass panes, compass | Forager; librarian | Maps, frames, banners |
| Armorer | Coal, iron, lava bucket, diamond | Charcoal; **player** | Iron and chain armour, bell, shield |
| Weapon smith | Coal, iron, flint, diamond | Charcoal; **player** | Iron axes, enchanted swords, bell |
| Tool smith | Coal, iron, flint, diamond | Charcoal, quarrier; **player** | Stone and iron tools, bell |
| Leatherworker | Leather, flint, leather pieces | Butcher; **player** | Leather armour, saddle |
| Butcher | Chicken, pork, rabbit, coal, mutton, beef, dried kelp, sweet berries | Forager; charcoal; **player** | Cooked meat, stew |
| Cleric | Rotten flesh, gold, rabbit foot, glass bottle, nether wart | **player** | Redstone, lapis, glowstone, pearls |
| Mason | Clay, stone, granite, andesite, diorite, quartz | Quarrier; **player** | Bricks, polished stone, terracotta |

The renewable core of a village is farmer, fisherman, shepherd, keeper and the
nitwit activities. Smiths, cleric and the iron, gold and diamond side of every
profession depend on the player, which is the core loop: the player mines, the
village turns raw materials into goods.

## Existing code and integration decisions

| Existing code | Use/change |
|---|---|
| `food.lua` | Falling points on the economic clock; eating from pouch and stash; hunger states |
| `farm_stock.lua` | Pouch functions move to `possessions.lua`; chest transfers stay |
| `farmer.lua` | `hand_over` limited to household, handout, pantry and paying buyers |
| `fisherman.lua` | A fish per completed cycle into the pouch |
| `flock.lua` | Shearing during the work stage |
| `keeper.lua`, `meal.lua`, `player_meals.lua` | Pantry, cooking, paid dinners, paid player meals |
| `gossip.lua` | Market news memory and exchange; demand and hunger terms beside reputation in the `wanted` wrapper |
| `conversation.lua` | No change beyond the exchange it already calls; end-of-conversation trade runs from there |
| `births.lua` | No change; hunger makes its food rule bite |
| `nitwit.lua` | No change; `labour.lua` gives nitwits work through `activity_override`, as the farmer and shepherd do |
| `common.lua` | `activity_override` answers for labour activities |
| `far_trips.lua` | Trade trips and labour sites count as errands |
| `builder.lua`, `builder_status.lua` | Builder posts its missing materials as news and buys them on trade trips; Buy buttons unchanged |
| `builder_bench_menu.lua` | Economy tab |
| `village_census.lua` | Economic weight in the building choice |
| `market.lua`, `bell.lua` | Stalls sell real surplus (ticket 12) |
| `diagnostic.lua` | Shows the economy fields |
| `builder_away.lua` | Unchanged; its stamp pattern is reused by `economy_clock.lua` |

## Saved state

New `_villages_*` entity fields, never to be renamed once released:

| Field | Holds |
|---|---|
| `_villages_econ_clock`, `_villages_econ_stamp` | Economic clock |
| `_villages_food_at` | Clock reading at which food points were last decayed |
| `_villages_endowed` | Starting stock given |
| `_villages_market_news` | Market news list |
| `_villages_labour` | Today's activity and the day it was chosen |
| `_villages_grove` | Positions of saplings a woodcutter planted |
| `_villages_tier_supply` | Days crafted from village supply at the current tier |

Existing fields reused: `_villages_farm_pouch` (every villager's pouch, emeralds
included), `_villages_food`, `_villages_fed_day`. Node metadata: `villages_owner` on
stash and pantry chests.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `living_villages_economy` | true | Turns the whole economy off; villagers behave as before this design |
| `living_villages_hunger_per_day` | 4 | Food points lost per game day of economic clock; 0 turns hunger off |
| `living_villages_stash_radius` | 8 | How far from its bed a villager's stash may be |
| `living_villages_craft_seconds` | 120 | Work seconds per crafted item |
| `living_villages_tier_supply_days` | 3 | Days of village-supplied crafting per tier |
| `living_villages_player_meal_price` | 1 | Emeralds a player pays for a tavern meal; 0 makes them free |

## Performance

- The clock stamp is one comparison per `do_custom` call and one write every 10 s.
- Ledgers are computed on demand, over a few dozen items, and cached per clock
  stamp.
- News is capped at 24 entries and shared only when a conversation ends.
- Stash reads touch one chest's inventory, only when a villager eats, crafts or
  trades.
- Labour site searches (berry bushes, generators) run on the route queue, once per
  morning, with the result cached on the villager for the day.

## Testing

Each new module gets a test in `tests/` that stubs the engine, as the existing ones
do. `ledger.lua`, `production.lua`'s recipes, `economy_clock.lua`'s gap rule and
`exchange.lua`'s settlement are pure and tested directly. A test checks every
recipe output against `trade_prices.lua`. `tools/lv_probe` gains an `LV_PROBE_ECONOMY`
mode that runs a village for several game days and logs per-day production,
consumption, trades, news spread and food levels, so pacing can be tuned on real
villages. `docs/economy-scenarios.md` holds manual in-game checks for what neither
can prove: the paid meal, theft gossip, the Economy tab and need bubbles.

## Tickets

Each ticket is one PR against the fork's `main`, on a `feature/economy-<n>-<slug>`
branch, and each leaves the game playable with `living_villages_economy` on or off.

| # | Ticket | Depends on |
|---|---|---|
| 1 | Economic clock, hunger, pantry dinners, paid player meals, the keeper's supply trips and cooking | — |
| 2 | `possessions.lua`: pouch for every villager, emeralds, stash claim and succession, starting stock | — |
| 3 | `tools/extract_trades/`, `trade_prices.lua`, `ledger.lua` (pure) | 2 |
| 4 | Farmer's distribution rules; fisherman's fish; shepherd's shearing | 1, 2, 3 |
| 5 | Market news in gossip | 3 |
| 6 | End-of-conversation exchange | 4, 5 |
| 7 | `labour.lua`: activity choice from news; forager and woodcutter | 5 |
| 8 | `production.lua`: jobsite crafting; restock tied to working | 3 |
| 9 | Demand and hunger price terms; tier advancement from village supply; theft gossip | 3, 8 |
| 10 | Economy tab, need bubble, inspector fields, census weight | 5 |
| 11 | Quarrier, porter, trade trips; the Builder buys from villagers | 6, 7 |
| 12 | Peddler; holiday market sells real surplus | 6, 11 |

### 1. Clock, hunger and the tavern

`economy_clock.lua`; falling points and hunger states in `food.lua`;
`tavern_pantry.lua` (the chests within 6 of the jukebox); `meal.lua` serves only what
the pantry holds and feeds the villager guest; `player_meals.lua` charges the player
into the pantry. Villagers have no emeralds before ticket 2, so they eat from the
pantry free. Hunger only sets the state here: its effects come with the tickets that
add what they act on (production in 4 and 8, prices and restocks in 8 and 9).

Every generated tavern already has a pantry: the stock schematic's chest stands 3
behind the jukebox, filled with ordinary village loot. So the pantry's supply lands
in the same ticket, or existing taverns would stop serving. `keeper_supply.lua`: in its
free hours, while the pantry holds fewer than 12 meals, the keeper walks to the work
chest of a farmer within 48 of the jukebox and carries back up to 24 bread, potatoes
and wheat; on shift it cooks one dish every 10 s (three wheat to a loaf, a potato
baked, a cod cooked); and a newly generated tavern's chest gets a starting stock on top
of its loot. Ticket 4 later turns the fetching into buying. A tavern with no chest (a
player's own) serves as before: a display that feeds no one and costs nothing.

Done when the tests show points falling with the clock and not without it, a pantry
dinner feeding its guest and emptying the pantry, an empty pantry serving nothing, a
player paying into the pantry or not being served, and the keeper fetching, delivering
and cooking; and a probe run shows a generated tavern's pantry stocked.

### 2. Possessions

Pouch API in `possessions.lua` over `_villages_farm_pouch`, `farm_stock.lua` on top
of it, stash claim by `villages_owner`, succession on bed change, starting stock,
drop on death for every villager. `keeper.lua`'s `take_over` clears
`_villages_farm_pouch` with the old job's fields; once the pouch holds a villager's
belongings it must keep it instead. Done when every villager carries a stock after
first activation and a dead villager's pouch drops.

### 3. Prices and ledger

The extraction tool, the generated table, the hand table for unlisted items, and
`ledger.lua`'s targets, need, surplus and value. Pure; no behaviour change yet.

### 4. Food distribution and real goods

`farmer.lua` household, handout, pantry and selling; fish per cycle; shearing.
Done when a farmer sells bread to a neighbour for emeralds, stocks the pantry and
still feeds its children free.

### 5. Market news

`_villages_market_news`, its exchange in `gossip.exchange`, listener-weighted
choice, decay. Done when a probe run shows a need spreading from one villager to
most of a village within two game days.

### 6. Exchange

`exchange.lua` settlement; end-of-conversation trades. Done when two villagers who
meet trade goods both value and their pouches show it.

### 7. Labour

`labour.lua` choice and the forager and woodcutter activities, with
`activity_override` and `far_trips.lua`. Done when nitwits and the unemployed gather
and sell, and the share choosing wood falls after its price does.

### 8. Jobsite crafting

`production.lua` recipes and crafting over the clock; restock wrapper. Done when a
toolsmith without inputs stops restocking and one with inputs makes tools.

### 9. Player-facing prices and tiers

Demand and hunger terms in the `wanted` wrapper; tier advancement from supply;
theft gossip. Done when a player sees a scarce good's price rise and a supplied smith
climbs a tier with no player trade.

### 10. Visibility

Economy tab, need bubble, inspector, census weight.

### 11. Trade trips and the Builder

Quarrier and porter activities; trade trips through `navigation.lua`; the Builder
posting and buying materials. Done when a Builder in `requires_materials` gets cobble
from a quarrier without a player.

### 12. Peddlers and the market

Peddler activity; `market.lua` stalls stocked from real surplus; browsers buy.

## Open questions

- Pacing: hunger rate, craft time and starting stock all need probe runs on real
  villages before they are more than guesses.
- Whether a peddler walks to another village is the start of the next phase, and
  needs its own design (routes between villages, news carried across them).
- Whether stashes should be protected from players beyond the gossip cost, for
  servers that want it, is left to a later setting.
