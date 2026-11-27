package game

import "core:math"

// Trade (Phase 3): Classic's model. Commodities have a base price; each island keeps a supply and a demand for every
// commodity, and a commodity's price there is base × demand ÷ supply. Goods are made of commodities, so a good's price
// is the sum over its recipe. An island sells at that price and buys 10% below it. Buying a good raises the island's
// demand for its commodities, selling raises the supply, one unit at a time, and every market drifts back to its
// usual level each turn. The goods list is Claude's draft, approved by the user on November 27, 2026.

START_MONEY :: 250
MONEY_MAX :: 1_000_000_000
HOLD_TONS :: 50 // the sloop's; see hold_tons
CARGO_MAX :: 10_000 // per good; far above what a hold can carry
GOODS_PER_ISLAND_MIN :: 2
GOODS_PER_ISLAND_MAX :: 6
MARKET_MIN :: 200 // supply and demand in thousandths, kept within 0.2 ..= 5.0
MARKET_MAX :: 5000
IMPACT :: 4 // thousandths of supply or demand moved per commodity unit traded
DRIFT :: 50 // each turn a market moves 1/DRIFT of the way back to its usual level
DISCOUNT :: 10 // percent: an island buys this far below its selling price
RATION_LOT :: 10 // rations come in lots of ten, priced at two grain

Commodity :: enum u8 {
	Grain,
	Fish,
	Timber,
	Wool,
	Ore,
	Spice,
}

COMMODITY_PRICE := [Commodity]int {
	.Grain  = 2,
	.Fish   = 3,
	.Timber = 4,
	.Wool   = 5,
	.Ore    = 8,
	.Spice  = 20,
}

Good :: enum u8 {
	Flour,
	Salt_Fish,
	Timber,
	Rope,
	Sailcloth,
	Woolens,
	Nails,
	Iron_Tools,
	Rum,
	Dyes,
	Cutlasses,
	Pepper,
	// Sea goods (Phase 8): no island trades them, but every island buys them. They come from whales and merfolk.
	Whale_Oil,
	Pearls,
	Coral,
}

LAND_GOODS :: int(Good.Pepper) + 1 // the save layout and the island markets cover these twelve

Good_Info :: struct {
	name:       string,
	recipe:     [Commodity]int,
	tons:       int,
	occurrence: int, // percent chance an island trades it
}

GOODS := [Good]Good_Info {
	.Flour      = {"Flour", #partial [Commodity]int{.Grain = 3}, 1, 70},
	.Salt_Fish  = {"Salt fish", #partial [Commodity]int{.Fish = 3}, 1, 60},
	.Timber     = {"Timber", #partial [Commodity]int{.Timber = 3}, 2, 50},
	.Rope       = {"Rope", #partial [Commodity]int{.Wool = 1, .Timber = 1}, 1, 50},
	.Sailcloth  = {"Sailcloth", #partial [Commodity]int{.Wool = 3}, 1, 40},
	.Woolens    = {"Woolens", #partial [Commodity]int{.Wool = 4}, 1, 40},
	.Nails      = {"Nails", #partial [Commodity]int{.Ore = 2}, 1, 40},
	.Iron_Tools = {"Iron tools", #partial [Commodity]int{.Ore = 2, .Timber = 1}, 1, 30},
	.Rum        = {"Rum", #partial [Commodity]int{.Grain = 2, .Spice = 1}, 1, 30},
	.Dyes       = {"Dyes", #partial [Commodity]int{.Wool = 1, .Spice = 1}, 1, 25},
	.Cutlasses  = {"Cutlasses", #partial [Commodity]int{.Ore = 3, .Timber = 1}, 1, 20},
	.Pepper     = {"Pepper", #partial [Commodity]int{.Spice = 2}, 1, 20},
	.Whale_Oil  = {"Whale oil", #partial [Commodity]int{.Fish = 5}, 2, 0},
	.Pearls     = {"Pearls", #partial [Commodity]int{.Spice = 3}, 1, 0},
	.Coral      = {"Coral", #partial [Commodity]int{.Spice = 1, .Ore = 1}, 1, 0},
}

Market :: struct {
	supply, demand: [Commodity]int, // thousandths
}

// The usual markets and the goods each island trades, from the world seed (not saved). The current markets start at
// the usual levels and are saved.
generate_markets :: proc(g: ^Game) {
	r := rng_make(g.seed ~ 0x3A_4B_E7_5E)
	for i in 0 ..< g.n_islands {
		for c in Commodity {
			g.usual[i].supply[c] = 600 + rng_below(&r, 801)
			g.usual[i].demand[c] = 600 + rng_below(&r, 801)
		}
		g.markets[i] = g.usual[i]
		trades: bit_set[Good]
		for _ in 0 ..< 20 {
			trades = {}
			for good in Good.Flour ..= Good.Pepper {
				if rng_below(&r, 100) < GOODS[good].occurrence {trades += {good}}
			}
			if card(trades) >= GOODS_PER_ISLAND_MIN {break}
		}
		for card(trades) > GOODS_PER_ISLAND_MAX { 	// drop at random until it fits the menu
			k := rng_below(&r, card(trades))
			for good in Good.Flour ..= Good.Pepper {
				if good not_in trades {continue}
				if k == 0 {
					trades -= {good}
					break
				}
				k -= 1
			}
		}
		if card(trades) < GOODS_PER_ISLAND_MIN {trades += {.Flour, .Salt_Fish}}
		g.trades[i] = trades
	}
}

commodity_price :: proc(m: ^Market, c: Commodity) -> f32 {
	return f32(COMMODITY_PRICE[c]) * f32(m.demand[c]) / f32(m.supply[c])
}

// What the island asks for one of the good.
sell_price :: proc(g: ^Game, i: int, good: Good) -> int {
	p: f32
	for c in Commodity {p += f32(GOODS[good].recipe[c]) * commodity_price(&g.markets[i], c)}
	return max(1, int(math.round(p)))
}

// What the island pays for one of the good.
buy_price :: proc(g: ^Game, i: int, good: Good) -> int {
	return max(1, sell_price(g, i, good) * (100 - DISCOUNT) / 100)
}

// A lot of ten rations costs two grain.
ration_price :: proc(g: ^Game, i: int) -> int {
	return max(1, int(math.round(2 * commodity_price(&g.markets[i], .Grain))))
}

// The good's worth away from any market: its commodities at base price.
base_value :: proc(good: Good) -> int {
	v := 0
	for c in Commodity {v += GOODS[good].recipe[c] * COMMODITY_PRICE[c]}
	return v
}

hold_used :: proc(g: ^Game) -> int {
	t := 0
	for good in Good {t += g.cargo[good] * GOODS[good].tons}
	return t
}

cargo_value :: proc(g: ^Game) -> int {
	v := 0
	for good in Good {v += g.cargo[good] * base_value(good)}
	return v
}

nudge :: proc(m: ^[Commodity]int, recipe: [Commodity]int) {
	for c in Commodity {m[c] = clamp(m[c] + recipe[c] * IMPACT, MARKET_MIN, MARKET_MAX)}
}

// Buy up to n of a good at the docked island, one at a time, stopping when money or hold space runs out. Returns how
// many were bought and what they cost.
buy :: proc(g: ^Game, good: Good, n: int) -> (count, cost: int) {
	i := g.docked
	if i == NO_ISLAND || good not_in g.trades[i] {return}
	for count < n {
		p := your_cost(g, i, good)
		if p > g.money || hold_used(g) + GOODS[good].tons > hold_tons(g) || g.cargo[good] >= CARGO_MAX {break}
		g.money -= p
		g.cargo[good] += 1
		cost += p
		count += 1
		nudge(&g.markets[i].demand, GOODS[good].recipe)
	}
	return
}

// Sell up to n of a good at the docked island, one at a time. Returns how many were sold and what they fetched.
sell :: proc(g: ^Game, good: Good, n: int) -> (count, takings: int) {
	i := g.docked
	if i == NO_ISLAND || (good not_in g.trades[i] && !is_sea_good(good)) {return}
	for count < n && g.cargo[good] > 0 {
		p := your_take(g, i, good)
		if g.money + p > MONEY_MAX {break}
		g.money += p
		g.cargo[good] -= 1
		takings += p
		count += 1
		nudge(&g.markets[i].supply, GOODS[good].recipe)
	}
	return
}

// Buy up to n lots of ten rations. Rations take no hold space.
buy_rations :: proc(g: ^Game, lots: int) -> (count, cost: int) {
	i := g.docked
	if i == NO_ISLAND {return}
	for count < lots {
		p := ration_price(g, i)
		if p > g.money || g.rations + RATION_LOT > RATIONS_MAX {break}
		g.money -= p
		g.rations += RATION_LOT
		cost += p
		count += 1
		nudge(&g.markets[i].demand, #partial [Commodity]int{.Grain = 1})
	}
	return
}

// Every market eases back towards its usual level, a step a turn.
drift_markets :: proc(g: ^Game) {
	ease :: proc(v: ^int, usual: int) {
		d := usual - v^
		if d == 0 {return}
		step := d / DRIFT
		if step == 0 {step = d > 0 ? 1 : -1}
		v^ += step
	}
	for i in 0 ..< g.n_islands {
		for c in Commodity {
			ease(&g.markets[i].supply[c], g.usual[i].supply[c])
			ease(&g.markets[i].demand[c], g.usual[i].demand[c])
		}
	}
}

// The price book: what each island asked for its goods when you last docked there, and when. Updated on docking and
// after every trade (the user's request, November 27, 2026: compare last viewed prices, with their age).
NEVER_SEEN :: -1

Seen :: struct {
	turn:  int, // NEVER_SEEN until you dock there
	price: [Good]int, // what the island asked (its selling price); 0 for goods it does not trade
}

record_prices :: proc(g: ^Game) {
	i := g.docked
	if i == NO_ISLAND {return}
	g.seen[i].turn = g.turn
	for good in Good {g.seen[i].price[good] = good in g.trades[i] ? sell_price(g, i, good) : 0}
}

// What the island would pay for a good it asked `asked` for (the same 10% below as buy_price).
paid_for :: proc(asked: int) -> int {
	return max(1, asked * (100 - DISCOUNT) / 100)
}

// Islands with a recorded price for the good, dearest first (best to sell at). Returns how many were written.
book_rows :: proc(g: ^Game, good: Good, out: []int) -> int {
	all: [ISLAND_MAX]int
	n := 0
	for i in 0 ..< g.n_islands {
		if g.seen[i].turn == NEVER_SEEN || good not_in g.trades[i] {continue}
		pos := n
		for pos > 0 && g.seen[all[pos - 1]].price[good] < g.seen[i].price[good] {
			all[pos] = all[pos - 1]
			pos -= 1
		}
		all[pos] = i
		n += 1
	}
	n = min(n, len(out))
	copy(out, all[:n])
	return n
}
