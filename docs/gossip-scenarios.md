# Gossip scenarios

Manual in-game checks for `gossip.lua`, for what the stubbed tests can't prove: the real trade window,
golems and the cure. Use a world on VoxeLibre with this mod, in survival mode (golems ignore creative
players). The Lookup Tool (`doc_identifier`, with the `server` or `debug` privilege) shows a villager's
`Gossip` line: each player's reputation and the entries behind it. `debug.txt` has a
`[living_villages] gossip` line for each event and share.

## Trading

Trade with a villager several times, then close the window and open it again.

- `Gossip` shows `trading` going up by 4 a trade, stopping at 25.
- At 20 or more, stackable goods cost one less on their first ingredient. Goods that don't stack cost
  more visibly less (4 less at 20).
- The payment taken matches the price shown.
- A second player opening the same villager sees the old price.

## Paging with items in the input

Put payment in the input slots, then page through the trades on a villager that likes or dislikes you.

- The output slot fills only when the input covers the price shown, not the base price.
- The payment taken matches the price shown. Check a price that a discount brings just within reach,
  and one that dislike puts just out of reach.
- A trade that locks or raises the villager's tier redraws the window at the same price.

## News travels by conversation

Hit villager A, out of sight of villager B, in a village's Putter stage.

- A shows `minor_negative 25`. B shows nothing.
- Once they finish a conversation, B shows `minor_negative 5`. A conversation broken off shares nothing.
- Hit A a few more times and B's value follows, at 20 less than A's. It doesn't grow by being retold.

## Keepers

Trade with a tavern keeper. Then watch it in the tavern during the evening, with guests standing near
its jukebox, and on a holiday between 10:30 and 14:30, when it's off shift during the bell gathering.

- If it talks with an idle villager, that villager's `Gossip` shows your `trading` less the sharing cost.
  Trade enough first: `trading` needs to be above 20 to survive being shared.
- While it talks on shift, its `Keeper` line still says `staffing the tavern`, and seated guests and
  players at tables keep being served. This is the check that matters.
- It stays at the jukebox and doesn't walk over to anyone.

## Killing

Kill a villager in plain view of another, and with a third behind a wall. One kill is enough: it puts a
witness at reputation -125, past the golems' -100.

- The witness shows `major_negative`, and its prices rise. The one behind the wall shows nothing.
- A kill by a mob or by fire adds nothing to anybody.
- Arrows you shoot count as your hits and kills.
- Near a witness at -100, a village or summoned iron golem attacks you. Away from anyone who knows, it doesn't.
- A golem you built with iron blocks and a pumpkin doesn't attack you.

## The cure

Cure a zombie villager with a golden apple, and give it a jobsite. VoxeLibre needs no weakness
potion, and the apple comes back. The cure takes 3 to 5 minutes, and the zombie must stay loaded,
out of sunlight.

- The click plays a growl and a burst of pink particles (`cure_feedback.lua`). The zombie then shakes
  steadily and gives off pink particles every second until the villager appears, with a chime and green
  particles. Another golden apple on it while it cures only puffs particles.
- `Gossip` shows `major_positive 20` and `minor_positive 25`, reputation 125, for whoever fed the apple.
- Its prices are discounted for that player, and not for another.

## Fading

Note a villager's values and wait 20 minutes of real time on the server, then look again.

- `trading` is down by 2, `minor_positive` by 1, `minor_negative` by 20, `major_negative` by 10.
  `major_positive` hasn't changed. Sleeping doesn't speed this up.
- With `living_villages_gossip` off, prices are vanilla's and nothing new is noted. Turned on again,
  the memories are still there, less what they have faded.
