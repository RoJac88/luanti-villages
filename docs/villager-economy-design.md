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

A villager eats when its points are at or below `FULL - 4` and it has food: from its
belongings, and then from its stash when it stands within 4 of it (`possessions.eat`,
checked once a minute). Tavern dinner is the other
place it eats (see [The tavern](#the-tavern)). Eating uses `food.receive` and
`food.show_handover`'s eating sound; food never goes on the ground.

An adult never fed (`_villages_food` unset) starts at 8 points, fed but not full, so
a new village is not found starving with nothing made and nothing restocked, and
births still wait on the farm (ticket 8, found when the first crafting probe made
nothing).

Children do not get hungry. Their household feeds them once a day, as now
(`_villages_fed_day`), and they take no part in trade.

## Possessions

`possessions.lua`.

- **Belongings.** `_villages_belongings`, item name to count, carried, dropped where
  the villager dies. It is kept apart from the work pouch (`_villages_farm_pouch`,
  `farm_stock.lua`), which the farmer, the Builder and the keeper treat as goods for
  their job: they empty it into work chests, wait for it to be empty, and drop it when
  the job goes. A shared pouch would have sent a farmer's emeralds into its farm chest
  and kept a Builder from ever finishing. The pouch stays the job's; belongings are
  the villager's.
- **Emeralds.** Held in the belongings as `mcl_core:emerald`.
- **Stash.** The chest nearest the villager's bed, within
  `living_villages_stash_radius` (8), claimed in the chest's meta: `villages_owner`
  (the villager's `_id`) and `villages_owner_bed` (the bed it was claimed from); both
  halves of a double chest. Generated chests and chests a player placed are eligible.
  Work chests never are: a tavern's pantry (within 6 of a jukebox), a farm's chest
  (beside a composter), a Builder's (within 6 of its bench). `farm_stock.find_chests`
  leaves stashes out, so farmers, Builders and keepers never take from one.
- **Succession.** A stash belongs to the bed. A villager whose bed is the one a chest
  was claimed from, and whose owner no longer holds that bed (vanilla's `villager` bed
  meta names someone else or no one), takes the chest and what is in it. A villager
  that moves to another bed gives up its old chest.
- **Starting stock.** 3 to 6 emeralds when a villager is first seen as an adult
  (`_villages_endowed`), and a kit (`KITS`: a farmer some seeds and bread, a smith a
  few coal and ingots) the first time it has a profession that has one
  (`_villages_kit`), once in its life, so taking a job away and back cannot mint more.
  A villager born in the village gets the same when it grows up: births are a source
  of emeralds, limited by food.
- **Theft.** A player who takes from a claimed stash within sight of a villager
  (gossip's witness rule: 16 nodes, line of sight, and awake) gives that villager
  `minor_negative` gossip, once a minute per witness and player however many stacks
  are taken (`theft.lua`, ticket 9). What was taken is written in the chest's meta
  (`villages_missing`); the owner finds it when it next looks, once a minute, and logs
  it. Its ledger counts the stash, so what it needed of the missing goods it now needs
  more, and market news carries that as "needs". Nothing is locked.

## Ledger and prices

`ledger.lua`, pure: no engine calls beyond what is passed in.

**Base prices.** `trade_tables.lua` is a checked-in copy of VoxeLibre's profession
trade tables, extracted by `tools/extract_trades/`. The tables are a `local` in
`mobs_mc/villager.lua` and are not exposed, so the tool cuts that block out and
evaluates it with stubs; it is rerun when the supported VoxeLibre version changes,
and `tests/trade_tables.lua` fails when the installed VoxeLibre no longer matches.
`ledger.lua` derives prices from the raw trades when first asked. A buy offer of N
items for E emeralds prices an item at E/N; a sell offer of N items for E emeralds
(and perhaps a second ingredient, at its own price) at the same. Where an item has
both, the base is their geometric mean. Items in no table (logs, cobble, saplings, sticks' sources)
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
| Fisherman | One completed cycle in four (`fisherman.lua`, which before only restocked) lands a fish by vanilla's fishing odds: cod in its barrel, up to 16, for the keeper to buy; anything else in its belongings, up to 8 of a kind |
| Shepherd | Every 90 s of the work stage shears a flock sheep within 4 that has its wool (`flock.lua`), 1 to 3 wool of its colour into its belongings, up to 16 a colour. Wool grows back when the sheep eats grass, as on vanilla sheep |
| Keeper | Cooks raw pantry ingredients into menu items (see [The tavern](#the-tavern)) |

### Jobsite crafting

Professions with no work loop craft at their jobsite (ticket 8). `recipes.lua` holds
one recipe list per profession, pure data that `ledger.lua` also reads: outputs from
that profession's sell offers, or inputs of its own recipes (paper and books for the
librarian's bookshelves), inputs from the real crafting recipe. A test checks every
output against the profession's trade table in `trade_tables.lua`. `production.lua`
does the making. Over work-stage economic clock time spent within 3 of its jobsite, a
villager banks seconds (`_villages_craft`) and makes a recipe's outputs at
`living_villages_craft_seconds` per item (default 120), taking the inputs from its
belongings and then its stash, wherever it stands. With no inputs it makes nothing and
banks nothing. A hungry villager works at half the rate, a starving one not at all.

It makes the recipe that adds most by its own values (the output's value less the
inputs' and the fuel's), among those it has inputs and fuel for and whose output it
holds fewer than its target plus 16 of. A surplus output's value falls, so a smith
moves from one tool to the next. Smelted goods take one furnace smelt each, and the
smiths one per ingot they forge. A coal or charcoal lump is 8 smelts, and the smelts
left over are kept (`_villages_fuel`). A crafting profession's ledger targets 4 crafts of
each recipe input, and 4 lumps of coal where its recipes smelt.

| Profession | Makes | From |
|---|---|---|
| Tool smith | Stone pickaxe, axe, shovel, hoe | Cobble, sticks |
| Weapon smith | Iron axe | Iron, sticks, fuel |
| Armorer | Iron helmet, chestplate, leggings, boots | Iron, fuel |
| Butcher | Cooked porkchop, cooked chicken | Raw meat, fuel |
| Fletcher | Arrows; flint; bows | Flint, sticks, feathers; gravel; sticks, string |
| Librarian | Paper; books; planks; bookshelves; glass | Sugar cane; paper, leather; oak logs; planks, books; sand, fuel |
| Leatherworker | Leather armour | Leather |
| Mason | Bricks; chiselled stone bricks; polished andesite, granite, diorite | Clay, fuel; stone; the raw stone |

The farmer, fisherman and shepherd make their goods in their own loops. The cleric's
goods have no recipe, and the cartographer's map needs a compass a village cannot make,
so these five restock as vanilla does. Enchanted goods are never made. Kits were
topped up so each crafting profession can make its first goods: feathers for the
fletcher, leather for the librarian, cobble for the tool smith, a fourth ingot for the
armorer and sticks for the weapon smith.

Charcoal counts wherever vanilla's tables ask for coal: the ledger counts the two
together toward one target, and fuel burns either, charcoal first. So a village can
supply its smiths from its own woodcutters, who burn charcoal (see below). The butcher's
cooked meat became food (porkchop 6, chicken 5).

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
| Woodcutter | A grove near its bed | Plants saplings, fells only trees grown from saplings it planted (positions kept on the villager, `_villages_grove`, at most 8), replants each one, and burns some logs into charcoal. Wild trees are never cut |
| Quarrier | A cobblestone generator within 32 | Mines cobble a player's water-and-lava machine makes (`mcl_core`'s "Lava cooling" ABM). Never digs terrain |
| Porter | Stashes of villagers who hire it | Carries goods for a buyer's trade trip, for a fee |
| Peddler | The village | Buys surplus below the going price and sells where it has heard of need, keeping the margin (ticket 12) |

Ticket 7 builds `labour.lua` with the forager and the woodcutter. The choice is made at
the first work tick of each game day (`_villages_labour`), from the best price heard
asked (market news "needs" entries) for each activity's goods times its rate (forager
12 a day: berries, apples, cane; woodcutter 10: logs, saplings); yesterday's counts
1.25 times. Foragers leave flowers and mushrooms, which do not come back once picked.
A woodcutter's grove spot is open grass 8 to 20 from its bed, with a clear 7 x 7 x 7
box above, no path, door or bed within 3, and 5 from its other trees; it takes its
first sapling from under a wild oak, at most once a day, and never cuts a wild tree.
Every species that grows from one sapling counts (oak, birch, spruce, jungle,
acacia), so a savanna village cuts acacia; a wild tree is told from a house's logs by
its own leaves above it. A trip to a tree ends on an open cell beside the trunk, and
a target it could not reach is passed over for 5 minutes.
From ticket 8, after each felling it burns 8 of the logs it carries past 16 into 7
charcoal, up to 32: eight logs smelted with one lump of the charcoal as fuel, in a clamp
by the grove rather than a furnace. Trips stay within 50 of the bed, so
`far_trips.lua` is not needed, and labour leaves `activity_override` alone: a nitwit's
work stage has no jobsite for vanilla to send it to. Apples (3 points) and sweet
berries (1) became food.

Ticket 11 adds the quarrier and the porter. A quarrier's cobble is a generator's when
lava and water both touch it from the side or above, which is where VoxeLibre's Lava
cooling ABM puts it; it mines within 32 of its bed, up to 64 (a Builder wants cobble by
the hundred), at a rate of 32 a day for the choice. A porter is open when the villager
has heard of a trade waiting (an item one villager needs and another has); its income
for the choice is 2, a fee or two; its work is the trips it is hired for.

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

`market_news.lua` holds it; `conversation.lua` calls its `exchange` beside
`gossip.exchange`, so gossip's own setting does not turn the market off. Each
listener's ledger view is worked out once per conversation. What each member knows is
fixed before anyone speaks, so news crosses one hop per conversation. An item it needs
offered, or has spare wanted, weighs 4 times more; freshness falls linearly over
`NEWS_DAYS` to a floor of a tenth; each hop divides the weight by one more. From
ticket 11 an entry that completes a trade the listener has heard of (an offer of what
it heard someone needs, or a want of what it heard someone has) weighs 4 times too:
probe runs showed a quarrier's cobble never reaching a Builder through villagers who
wanted neither.

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

Ticket 6 settles the first channel (`exchange.lua`). Each pair makes the one trade
that gains the two of them most, buyer's value less seller's, over the goods the buyer
needs and the seller has spare and carries (a stash is not at hand). Emerald
payments are whole: a sale worth under one emerald grows to the fewest items that make
one, if the seller has them spare, and either payment goes through only when the buyer
values what it gets at no less than it pays and the seller at no more. Barter pays in
the one good the seller needs that leaves the buyer the most. The views are worked out
afresh for each pair, so a trade earlier in the same conversation counts.

Ticket 11 settles the second (`trade_trips.lua`). A need is urgent at a value 2 times
its price or more. The buyer picks, of the sellers it has heard have the item spare at
a value under its own and live within 64 of its bed, the need worth most, then the
nearest. It walks to the seller's bed: a seller within 8 sells in person, from its
belongings, as at the end of a conversation. A seller away from home carries its goods,
so a loaded one within 64 of its bed is followed, up to 3 walks; failing that the buyer
walks on to the seller's claimed stash and buys from the chest at the midpoint of its
value and the value it heard, whole emeralds into the chest. Either way it buys no more
than its emeralds pay for, and with none it plans no trip. Own trips run in the putter
stage, and the Builder's in its work stage too while short. A trip is dropped when the
day turns; a seller that came to nothing is passed over for 10 minutes.

A porter is hired when a conversation ends, after its trades: by a member with a
job (a jobsite, the keeper or the Builder), an urgent need with a known seller,
somewhere to deliver (its stash, the Builder's nearest bench chest) and 2 emeralds
or more. It gets a purse of up to 8, buys at its client's value in its work stage,
delivers the goods and the change, and keeps a fee of 1 if it bought anything. A
failed trip brings the whole purse back, the next day if need be.

The Builder (`builder_market.lua`), while short in `requires_materials`, puts its
missing priced materials in its ledger as `extra`, so its news posts them and it values
them urgently; unpriced ones (stone bricks, sand) only a player brings. It moves what
it bought into its pouch, where the bill counts it, and tops its purse up to 8 from
emeralds left in its bench chests.

## The farmer's food

`farmer.lua`'s `hand_over` gives food only to:

- itself, its household (villagers whose beds are within 5 across and 4 up or down of
  its own, which is as near as beds tell to the same house) and every child, free;
- anyone else who has an emerald and carries no food: a bundle, as many as vanilla's
  trades sell for one emerald (6 loaves, 26 potatoes), of which it eats what it wants
  and keeps the rest;
- a villager at 0 points that cannot buy, one item free (a farmer's handout);
- the tavern: the keeper buys from its chest (see [The tavern](#the-tavern)); the
  farmer collects the emeralds left there when it next stores its surplus.

With the economy off it feeds everyone free, as before.

## The tavern

- **Pantry.** The chests within 6 of the keeper's jukebox; the stock tavern's chest
  stands 3 behind it. The keeper fetches food for it from the farms' chests and the
  fishermen's barrels, and from ticket 4 buys it: it takes up to 8 emeralds from the
  pantry and leaves what it takes is worth at vanilla's prices, rounded, in the work
  chest. A pantry may run short of money, so the keeper takes the food even when it
  cannot pay all of it.
- **Cooking.** The keeper turns raw pantry items into its menu items over its shift:
  bread from wheat, baked potatoes from potatoes, cooked fish from raw fish.
- **Dinner.** `meal.lua` serves a guest only when the pantry has a menu item: it
  takes the item, the guest gains its food points and pays one emerald from its
  belongings into the pantry (from ticket 8). The keeper and its household (beds in
  the same house, `possessions.same_house`) eat free. A guest is served only at or
  below 8 points, the mark at which it eats what it carries, so one fed from home
  keeps its emeralds; one that cannot pay is not served. With an empty pantry the
  guest is seated and nothing is served. From ticket 11b every payment is logged:
  diner, price and pantry.
- **Player meals.** `player_meals.lua` takes the meal from the pantry and charges
  the player one emerald from their inventory before serving. A player with no
  emerald, or a tavern with an empty pantry, is not served and the log says which.
- **Player trades.** The keeper's menu trades stay vanilla (unlimited). A low pantry
  raises the player's price through the demand term.

## Rent

Ticket 11b. Longer probe runs of ticket 11 showed money going one way. Every villager
pays the tavern for dinner, the keeper pays farmers and fishermen for food, and there it
stops: a food producer earns several emeralds a day and spends one, while a villager
whose goods no one needs urgently, the Builder above all, loses one a day until it can
buy nothing. In one run a Builder bought 34 cobble from a quarrier for 2 emeralds, had
none left for the last 8, and never finished the house. Rent takes money from where it
piles up to the Builder, which spends it on materials, which quarriers and woodcutters
spend at the tavern. The Builder grows richer as the village grows.

- **Landlord.** Rent is owed to a Builder's bench, not to the villager holding it, so a
  new Builder inherits the income. Paid by errand, it goes in the bench chests, from which
  `builder_market.lua` already tops up the Builder's purse. A village with no claimed
  bench collects none.
- **Tenants.** A villager whose bed is in a house the Builder built: `finish_building`
  writes the bench's position as `villages_landlord` into the meta of every bed in the
  footprint. In a generated village farmers and fishermen pay as well, as if their
  houses had been built for them, so money starts flowing out of the food producers.
  Their landlord is the nearest claimed bench within `VILLAGE_RADIUS` (128) of the bed.
  The Builder, the keeper and its household (`possessions.same_house`) and children pay
  nothing.
- **How much.** `RENT` (1) emerald every `RENT_DAYS` (2) days of economic clock, so a
  villager away from players owes nothing for that time. Both numbers are guesses for
  probe runs to settle.
- **Arrears.** Rent not paid stays owing, up to `RENT_CAP` (3) emeralds; past that it
  is forgiven. No one is evicted. A tenant pays only from emeralds above the price of a
  dinner, so it eats first and pays when it next has money.
- **Paying.** At the end of a conversation with its landlord's Builder, before trades, a
  tenant hands over what it owes, from belongings to belongings, as `exchange.lua`
  settles a trade. A tenant owing the full cap pays by errand instead: a `far_trips.lua`
  errand in its putter stage to the bench's nearest chest, where it leaves the emeralds.
- **Where it goes.** The Builder pays for materials and dinner as before, from its
  belongings and its purse top-up. While the census has a building to put up it keeps
  buying; with none, rent piles up on the bench, and the census below shows it.
- **Observability.** Dinner payments are logged (The tavern), and so is every rent
  payment (tenant, amount, bench, at a conversation or by errand) and arrears forgiven.
  The probe census records each villager's emeralds, the pantry's and each bench
  chest's, so a run shows where money sits day by day. The inspector gets a `Rent`
  line: landlord, owed, last paid.

## What the player sees

**Prices.** Java's demand term, which `gossip.lua` left out "since neither exists
here", now exists (`demand.lua`, ticket 9). The ledger's urgency for an offer's item
moves the first ingredient of that trade for every player, through the same `wanted`
list wrapper reputation uses, combined with reputation in one place: the demand term
moves the base count first, then reputation moves that. The urgency (the trader's
value over the base price, 0.5 to 3) moves the price by its square root, so a full
need is about 1.7 times. A villager short of what it buys pays more for it, asking
fewer items for its emerald (a smith out of coal takes 9 lumps, not 15); one with a
glut of what it sells sells cheaper. A hungry villager charges 1.25 times for what it
sells and a starving one 1.5 times: it works slower, so its goods are scarcer.
Counts stay between 1 and a stack. With gossip off the demand term still applies;
with the economy off only reputation does.

**Restocking.** Vanilla restocks a villager's locked trades in `unlock_trades` when
it arrives at its jobsite (`mobs_mc/villager.lua`, `do_work`). Both are local to
VoxeLibre's file, so `production.lua` wraps `do_custom` instead: when a call turns the
order to "work" and changes `_trades`, it puts `_trades` back for a starving villager,
and for a crafting profession that cannot make one craft from what its belongings and
stash hold. It tries again on its next arrival. The fisherman's per-cycle restock is
unchanged.

**Tiers.** Vanilla raises `_max_trade_tier` when a player first uses a trade at
the top tier, or with a 1 in 5 chance on a freshly restocked one. In addition, a
villager that has crafted on `living_villages_tier_supply_days` (3) separate days at
its current tier, entirely from inputs it bought from villagers or produced itself,
goes up one tier, up to 5. Both routes run; the faster one wins. `production.lua`
counts a craft as village supply when its inputs and fuel all came from belongings:
belongings fill only from the kit, the villager's own work and trades with villagers,
while a stash may hold what a player left. The kit counts, as the village's start.
The days are kept in `_villages_tier_supply` ({tier, days, day}). Going up sets
`_max_trade_tier`, `_max_tradenum` and the badge, mirroring vanilla's file-local
`update_max_tradenum` and `set_textures`.

**Visibility.**

- **Economy tab** on the Builder's bench (`builder_bench_menu.lua`, from
  `economy_report.lua` through `builder.economy`), in two labelled halves. *Heard by
  the Builder*: shortages and gluts, its market news (own and hearsay) summed by item
  with how many villagers and items, and the missing professions: those that make
  what the village is short of when none of that item's producers is present, worst
  (most worth answered) first. *Seen around the bench*: the loaded adult villagers
  within 128: professions present (the keeper and the Builder by role), nitwits and
  the unemployed with today's activity, and goods made and used today and yesterday.
  Made and used come from each villager's tally (`economy_tally.lua`,
  `_villages_tally`): crafts with their inputs and lumps, gathering and charcoal,
  meals. With no Builder loaded nothing is heard; with the economy off it says so.
- **Need bubble** (`need_bubble.lua`). Once a second, a ray from each player's eye
  along its look, 8 nodes; the first object, if an adult villager, shows that player
  a particle of its top need by worth (the first of its ledger's needs, as the
  inspector's Needs line orders them) over its head. A node or another object in the
  way hides it.
- **Census.** `village_census.lua`'s pick takes a `favoured` set whose shares count
  double in the deficit: the stock buildings holding the worst gap's jobsite
  (`economy_report.BUILDINGS`, read from VoxeLibre's schematics: farm, tavern and
  medium house, small house, large house, blacksmith, library, butcher, church; none
  holds a weapon smith's, tool smith's or mason's). The bench menu's choice of a
  schematic source still overrides it. The Builder logs the gap with its choice.
- **Inspector.** `diagnostic.lua` shows a villager's food, clock, belongings, stash,
  needs, surplus, news, labour and crafting, and now its trade tier with the days of
  village supply toward the next and what it made and used today.

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
| `farmer.lua` | `hand_over` limited to household, children, handout and paying buyers |
| `fisherman.lua` | A catch one cycle in four: cod into its barrel, other fish into its belongings |
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
| `_villages_belongings` | What a villager owns and carries, emeralds included |
| `_villages_endowed` | Emeralds given |
| `_villages_kit` | The profession whose kit it was given |
| `_villages_stash` | Its stash chest's position (the claim itself is in the chest's meta) |
| `_villages_market_news` | Market news list |
| `_villages_labour` | Today's activity and the day it was chosen |
| `_villages_grove` | Positions of saplings a woodcutter planted |
| `_villages_sapling_day` | The day a woodcutter last took a sapling from under a wild oak |
| `_villages_craft` | Work seconds banked toward the next crafted item |
| `_villages_fuel` | Furnace smelts left from the last coal or charcoal lump burned |
| `_villages_tier_supply` | Days crafted from village supply at the current tier |
| `_villages_tally` | What it made and used today, and yesterday |
| `_villages_trade_trip` | A trade trip under way: item, seller, legs, a porter's client and purse |
| `_villages_builder_wants`, `_villages_builder_drop` | A short Builder's missing priced materials, and its delivery chest |
| `_villages_rent` | Rent owed, the clock reading it was last charged at, and the last payment |

Existing fields reused: `_villages_food`, `_villages_fed_day`. Node metadata:
`villages_owner` and `villages_owner_bed` on stash chests, and `villages_missing`
(what a player took, until the owner looks). From ticket 11b, `villages_landlord` on
beds the Builder built: the bench they owe rent to.

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
recipe output against `trade_tables.lua`. `tools/lv_probe` gains an `LV_PROBE_ECONOMY`
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
| 3 | `tools/extract_trades/`, `trade_tables.lua`, `ledger.lua` (pure) | 2 |
| 4 | Farmer's distribution rules; fisherman's fish; shepherd's shearing | 1, 2, 3 |
| 5 | Market news in gossip | 3 |
| 6 | End-of-conversation exchange | 4, 5 |
| 7 | `labour.lua`: activity choice from news; forager and woodcutter | 5 |
| 8 | `production.lua`: jobsite crafting; restock tied to working | 3 |
| 9 | Demand and hunger price terms; tier advancement from village supply; theft gossip | 3, 8 |
| 10 | Economy tab, need bubble, inspector fields, census weight | 5 |
| 11 | Quarrier, porter, trade trips; the Builder buys from villagers | 6, 7 |
| 11b | Rent to the Builder's bench; dinner and rent logging; emeralds in the probe census | 1, 11 |
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

`possessions.lua`: belongings apart from the work pouch, emeralds, kits, the stash
claim with its work-chest exclusions and succession, drop on death; stashes left out of
`farm_stock.find_chests`. `keeper.lua`'s `take_over` drops the old job's pouch instead
of deleting it. Villagers still eat at the tavern free: with no income before tickets 4
and 6, paying for dinner would only run their emeralds out. Done when every villager
owns its emeralds and kit after first activation, claims a stash by its bed that no
work chest is, and drops its belongings on death.

### 3. Prices and ledger

The extraction tool, the generated table, the hand table for unlisted items, and
`ledger.lua`'s targets, need, surplus and value. Pure; no behaviour change yet,
beyond the inspector showing each villager's top needs and surplus
(`possessions.assess`, from its belongings, stash and food).

### 4. Food distribution and real goods

`farmer.lua` household, handout and selling; the keeper buying at work chests and
barrels; eating from belongings and stash; fish per cycle into the barrel; shearing.
Villagers still dine at the tavern free: only farmers and fishermen earn yet, so
paying would run everyone else's emeralds out before ticket 8 gives them something to sell.
Done when a farmer sells bread to a neighbour for emeralds, the keeper pays for what
it fetches, and a farmer still feeds its children free.

### 5. Market news

`_villages_market_news`, its exchange in `gossip.exchange`, listener-weighted
choice, decay. Done when a probe run shows a need spreading from one villager to
most of a village within two game days.

### 6. Exchange

`exchange.lua` settlement; end-of-conversation trades. Done when two villagers who
meet trade goods both value and their pouches show it. Villagers still dine at the
tavern free: trading moves goods between them, but most professions make nothing to
sell until ticket 8, so paying for dinner waits for that ticket.

### 7. Labour

`labour.lua` choice and the forager and woodcutter activities. Done when nitwits and
the unemployed gather and sell, and the share choosing wood falls after its price does.

### 8. Jobsite crafting

`production.lua` recipes and crafting over the clock; restock wrapper. Done when a
toolsmith without inputs stops restocking and one with inputs makes tools.

Landed with it: `recipes.lua`, read by the ledger too, so crafting professions want
and buy their inputs; charcoal counted as coal and burned by woodcutters; cooked meat
as food; the kits topped up; and villagers paying an emerald for tavern dinners, now
that every crafting profession has goods to sell.

### 9. Player-facing prices and tiers

Demand and hunger terms in the `wanted` wrapper; tier advancement from supply;
theft gossip. Done when a player sees a scarce good's price rise and a supplied smith
climbs a tier with no player trade.

Landed as `demand.lua` (applied in `gossip.lua`'s priced window), the tier count in
`production.lua`, and `theft.lua` (wrapping the chests' take callback).

### 10. Visibility

Economy tab, need bubble, inspector, census weight.

Landed as `economy_tally.lua`, `economy_report.lua` (read by `builder.economy` for the
tab and the census), `need_bubble.lua`, the tab in `builder_bench_menu.lua`, `pick`'s
`favoured` in `village_census.lua`, and the inspector's `Trade tier` and `Today` lines.
The Builder, a mason to vanilla, no longer crafts or wants as one. `docs/economy-scenarios.md`
holds the manual checks.

### 11. Trade trips and the Builder

Quarrier and porter activities; trade trips through `navigation.lua`; the Builder
posting and buying materials. Done when a Builder in `requires_materials` gets cobble
from a quarrier without a player.

Landed as the quarrier and porter in `labour.lua`, `trade_trips.lua` (installed in
`init.lua`, which also hands it the end of each conversation for hiring),
`builder_market.lua`, `exchange.offer`'s single-item form, the trade trip as a
`far_trips.lua` errand and a busy field for `conversation.lua`, and the inspector's
`Trade trip` and `Builder wants` lines.

### 11b. Rent

Rent owed to the Builder's bench by the tenants of its houses and, in a generated
village, by farmers and fishermen; paid at the end of a conversation with the Builder,
or by errand to the bench chest once the arrears reach the cap. Dinner and rent
payments logged; the probe census records the emeralds of each villager, the pantry and
each bench chest; the inspector's `Rent` line. Done when a probe run of six game days,
with ticket 11's staging (a small house and a cobble generator), shows rent reaching the
bench from farmers and fishermen and the Builder finishing the house without a player,
and the census shows where the village's emeralds sit on each day.

### 12. Peddlers and the market

Peddler activity; `market.lua` stalls stocked from real surplus; browsers buy.

## Open questions

- Pacing: hunger rate, craft time, starting stock and rent all need probe runs on
  real villages before they are more than guesses.
- Whether the Builder becomes the next place money piles up, once the census has
  nothing left to build. If so, the Builder could spend its surplus on upkeep, or rent
  could fall with its savings.
- Whether a peddler walks to another village is the start of the next phase, and
  needs its own design (routes between villages, news carried across them).
- Whether stashes should be protected from players beyond the gossip cost, for
  servers that want it, is left to a later setting.
