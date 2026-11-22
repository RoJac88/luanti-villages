# Reads the A log then the B log (lv_keep and living_villages lines) and prints one row
# per game day with both sides, then the means over the days both reached. Run by
# compare.sh. Columns per side:
#   din   diners at the tavern that evening / the keeper's demand
#   $     the posted dinner price
#   hun   hungry + starving adults at the work bell / adults
#   money all villagers' emeralds, and the top three's share
#   trd   trades (sales face to face and from stashes), and their emeralds
#   dish  dishes the butcher cooked
#   kb    lots the keeper bought
#   fail  trade trips given up
#   dead  villagers that died
FNR == 1 { side = (side == "") ? "a" : "b"; cur = "" }
/\[lv_keep\] work start day / {
	match($0, /day [0-9]+/); cur = substr($0, RSTART + 4, RLENGTH - 4) + 0
	if (cur < from) { cur = ""; next }
	days[cur] = 1
	match($0, /: [0-9]+ adults/); adults[side, cur] = substr($0, RSTART + 2, RLENGTH - 9) + 0
	match($0, /hungry=[0-9]+/); h = substr($0, RSTART + 7, RLENGTH - 7) + 0
	match($0, /starving=[0-9]+/); s = substr($0, RSTART + 9, RLENGTH - 9) + 0
	hungry[side, cur] = h + s
	next
}
/\[lv_keep\] tavern day / {
	match($0, /day [0-9]+/); d = substr($0, RSTART + 4, RLENGTH - 4) + 0
	match($0, /dined=[0-9]+/); dined[side, d] = substr($0, RSTART + 6, RLENGTH - 6) + 0
	next
}
/\[lv_keep\] food [0-9a-f]+ keeper / { split($0, f, "food "); split(f[2], g, " "); keeper[side] = g[1] }
cur == "" { next }
/\[lv_keep\] dinner / {
	match($0, /posted=[0-9]+/); price[side, cur] = substr($0, RSTART + 7, RLENGTH - 7)
	match($0, /demand=[0-9]+/); demand[side, cur] = substr($0, RSTART + 7, RLENGTH - 7)
	next
}
/\[lv_keep\] money total=/ && !((side, cur) in money) {
	match($0, /total=[0-9]+/); money[side, cur] = substr($0, RSTART + 6, RLENGTH - 6)
	match($0, /top3=[0-9]+%/); top3[side, cur] = substr($0, RSTART + 5, RLENGTH - 5)
	next
}
/\] trade: villager [0-9a-f]+ sold / || /\] villager [0-9a-f]+ bought .* stash for / {
	trades[side, cur]++
	if (match($0, /for [0-9]+ emerald/)) em[side, cur] += substr($0, RSTART + 4, RLENGTH - 12)
	if (keeper[side] != "" && index($0, " to " keeper[side] " ")) kbuys[side, cur]++
	next
}
/\(butcher\) made [0-9]+ [a-z_]+:[a-z_]*(cooked|baked)/ { dish[side, cur]++; next }
/\] trade trip: villager [0-9a-f]+ gave up/ { fails[side, cur]++; next }
/\] villager [0-9a-f]+ died at / { dead[side, cur]++; next }
function cell(s, d) {
	return sprintf("%3s/%-3s %2s %2s/%-2s %5s %3s %3d %4d %3d %2d %3d %d",
		(s, d) in dined ? dined[s, d] : "-", (s, d) in demand ? demand[s, d] : "-",
		(s, d) in price ? price[s, d] : "-", (s, d) in hungry ? hungry[s, d] : "-",
		(s, d) in adults ? adults[s, d] : "-", (s, d) in money ? money[s, d] : "-",
		(s, d) in top3 ? top3[s, d] : "-", trades[s, d], em[s, d], dish[s, d], kbuys[s, d],
		fails[s, d], dead[s, d])
}
function add(s, d) {
	n[s]++; sd[s] += dined[s, d]; sdem[s] += demand[s, d]; sp[s] += price[s, d]; sh[s] += hungry[s, d]
	st[s] += trades[s, d]; se[s] += em[s, d]; sdi[s] += dish[s, d]; sk[s] += kbuys[s, d]
	sf[s] += fails[s, d]; sx[s] += dead[s, d]
}
END {
	head = "din/dem  $ hun   money top trd   em dsh kb fai x"
	printf "%5s | %-44s | %-44s\n", "day", "A " head, "B " head
	count = 0
	for (d in days) list[++count] = d + 0
	for (i = 2; i <= count; i++) { v = list[i]; for (j = i - 1; j >= 1 && list[j] > v; j--) list[j + 1] = list[j]; list[j + 1] = v }
	for (i = 1; i <= count; i++) {
		d = list[i]
		printf "%5d |   %s |   %s\n", d, cell("a", d), cell("b", d)
		# Means over days both sides finished: the evening and the next morning are in.
		if (("a", d) in dined && ("b", d) in dined) { add("a", d); add("b", d) }
	}
	if (n["a"] == 0) { print "no day both sides finished yet"; exit }
	printf "\nmeans over %d days both finished:\n", n["a"]
	printf "%-6s %7s %7s %6s %6s %7s %8s %6s %6s %7s %5s\n", "", "diners", "demand", "price", "hungry", "trades", "emeralds", "dishes", "keeper", "fails", "dead"
	for (k = 1; k <= 2; k++) {
		s = k == 1 ? "a" : "b"
		printf "%-6s %7.1f %7.1f %6.2f %6.1f %7.1f %8.1f %6.1f %6.1f %7.1f %5d\n", toupper(s), sd[s] / n[s], sdem[s] / n[s],
			sp[s] / n[s], sh[s] / n[s], st[s] / n[s], se[s] / n[s], sdi[s] / n[s], sk[s] / n[s], sf[s] / n[s], sx[s]
	}
}
