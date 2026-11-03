# Farmer scenarios

Manual in-game checks for the farmer. Use a world on VoxeLibre with this mod. The Lookup Tool
(`doc_identifier`, with the `server` or `debug` privilege) shows a villager's `Farm`, `Farm pouch`
and `Food` lines. Farmers work from 07:00 to 15:30 on ordinary days, not holidays.

## A stock farm with no chest in range

Find a village farm with no blacksmith or tavern chest within 32 nodes of its composter.

- The farmer harvests mature crops and replants, and its pouch fills with real items.
- The composter's level rises, and it collects bone meal and uses it on the least-grown crops.
- Nothing is left on the ground apart from inedible drops such as poison potatoes.
- Villagers nearby get food. Check `Food` rising on one.
- Place a chest within range. Within a minute or so of the farmer having a surplus, it walks there
  and stores it.

## A new field

Place a composter on open grass beside water, with a path nearby, and let a villager claim it. Give it
seeds by putting them in a chest in range.

- It fetches seeds, tills beside the water, sows, and grows the field outward.
- The field stops at `living_villages_farm_max_plots`.
- Ground out of reach of the water stays grass, and the path stays a path.

## Losing a farmer

Kill a farmer that holds goods and a part-filled composter.

- Its pouch drops where it died.
- Within about a minute the composter empties, and an unemployed villager can take the job.
- A composter you filled yourself, with no farmer involved, keeps its compost.

## Taking the job

With an unemployed adult villager and every other workstation free:

- A free composter it can reach, even with a barrel right beside it, and it walks to the composter. The Lookup Tool's `Composter sought` line names it.
- A composter 90 nodes away, with nothing nearer, and it still goes. It would not at 100 unless `living_villages_farm_job_radius` is raised.
- A free jukebox or pulpit beside it doesn't tempt it either until it is a farmer or there is no composter.
- Wall the composter off: within a minute it gives up (`Composter sought: none`) and can take the barrel.
- Two villagers and one composter: one becomes a farmer, and the other then takes another job.

## Births

With a free bed and two adult villagers who own beds nearby:

- Unfed (`Food` under 12), they have no child, however many days pass.
- Fed to 12 or more, they have one in the morning, and each loses 12 points.
- Feeding two of them bread by hand still works as before, fed or not.
- With `living_villages_births_need_food` off, births ignore food.

## Removing the mod

Remove the mod from a world where farmers have worked.

- The world loads, and villagers keep working as vanilla ones.
- The farmers' pouches are not recovered.
