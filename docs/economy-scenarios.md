# Economy scenarios

Manual in-game checks for the villager economy (`docs/villager-economy-design.md`) that the stubbed
tests and the headless probe can't make: the parts a player sees or does. Use a world on VoxeLibre
with this mod and `living_villages_economy` on, in survival mode. The Lookup Tool (`doc_identifier`,
with the `server` or `debug` privilege) shows a villager's `Food`, `Belongings`, `Stash`, `Needs`,
`Market news`, `Crafting`, `Trade tier` and `Today` lines. `debug.txt` has a `[living_villages]` line
for each sale, craft, theft and tier.

## Paid tavern meals

Sit at a tavern chair at a table with a plate, while the keeper is on duty, with emeralds in your
inventory, then without.

- In a tavern with a pantry, the keeper serves you and an emerald goes from your inventory into the
  pantry. A tavern with no pantry serves free.
- Without an emerald, it doesn't serve you, and the log says so. With
  `living_villages_player_meal_price = 0` it serves you free.
- A villager diner pays an emerald too, unless it lives in the keeper's house. One that isn't hungry
  (more than 8 food points) isn't served.

## Prices

Find a tool smith with no coal (`Needs` lists coal first), and open its trades.

- The coal trade asks fewer than vanilla's 15 lumps for its emerald (about 9 with none held).
- Give it coal, by letting it trade with villagers or by putting coal in its stash, and wait a minute:
  the price goes back toward 15.
- Let it go hungry (`Food` under 8 points, `hungry`): what it sells costs a quarter more.
- A player it likes sees the reputation discount on top of the demand price.

## Restocking

Trade a crafting villager out of an offer, then watch it arrive at its jobsite.

- With something to craft from, the offer unlocks as in vanilla.
- With its belongings and stash empty of every recipe's inputs, or starving, it doesn't, and
  `debug.txt` says `did not restock`.

## Tiers from village supply

Watch a mason or librarian with its kit for three working days, with no player trading with it.

- `Trade tier` counts the days: `tier 1, 1/3 days of village supply`, then 2/3.
- On the third day `debug.txt` says `rose to tier 2 on village supply`, its badge turns to iron, and
  its trade window shows the tier 2 offers.

## Theft

Open a villager's stash chest (the Lookup Tool's `Stash` line) with another villager watching from
a few nodes away, and take a stack.

- `debug.txt` says `theft: <you> took ...`, `seen by 1`. The watcher's `Gossip` shows
  `minor_negative` for you. Taking more within a minute adds nothing more.
- Behind a wall, or with every villager asleep, nobody sees it.
- Within a minute the owner logs `found ... gone from its stash`, and its `Needs` rises for what was
  taken, if it needed it.

## Economy tab

Right-click a Builder's bench and open the Economy tab, with the Builder nearby.

- The left half says what the Builder has heard: shortages and gluts with how many villagers, and
  missing professions. Talk the Builder into a few conversations (the Putter stage) and they fill.
- The right half lists the professions loaded around the bench, nitwits with their labour, and what
  was made and used today and yesterday. It matches the villagers' `Today` lines.
- With the Builder away, the left half says there is no news. Refresh reads it again.
- When a missing profession has a stock building (a library for a librarian), the Builder's next
  `will put up` line in `debug.txt` names the gap, and the bench's Default tab shows that building as
  next more often.

## Need bubbles

Look at an adult villager from within 8 nodes.

- An icon of the first item on its `Needs` line floats over its head, for you only. Another player
  looking elsewhere sees nothing.
- Look away, step back past 8 nodes, or stand behind a wall or another mob, and it goes within a
  second.
- A villager with no needs shows nothing, and a child shows nothing.

## Quarrier

Build a cobblestone generator (lava, a gap, water) within 32 of a nitwit's bed, and let a Builder
short of cobble post its need.

- The nitwit's `Labour` line turns `quarrier` on a morning after it has heard the need, and
  `debug.txt` shows `gathered 1 mcl_core:cobble` as it mines; the generator refills.
- Natural cobble, and cobble beside lava alone, is never touched.
- It stops at 64 cobble until it sells some.

## Trade trips and the Builder

Leave a Builder in `requires_materials` short of cobble, with no player bringing any, and a quarrier
selling it.

- `Builder wants` lists the cobble; any emeralds left in its bench chests move into its belongings
  (`took N emerald(s) ... to buy materials`).
- In its work stage it walks to the quarrier's home (`trade trip: ... sets off`), buys in person or
  from the quarrier's stash, and its next materials check moves the cobble into its pouch: the
  status window's carried count rises.
- With enough bought, the project starts with no player.

## Porters

With a nitwit whose `Labour` is `porter`, let it finish a conversation with a smith short of coal
that has heard of a seller.

- `debug.txt` says `hired porter`; the smith's emeralds go down by the purse.
- In its work stage the porter walks to the seller, then to the smith's stash, and leaves coal and
  change there (`porter ... delivered`), keeping one emerald.
