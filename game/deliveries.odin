package game

import "core:math"

// Districts and deliveries (Phase 4). Every island has docks and a market; some have a delivery service, a street
// vendor, or a dark alley (opened in Phase 5). The delivery service offers jobs in Classic's words; the user chose up
// to three carried at once, with a deadline of about twice the distance (the C++ rule) and half pay when late, and a
// street vendor selling cheap rations (November 27, 2026).

District :: enum u8 {
	Delivery_Service,
	Street_Vendor,
	Dark_Alley,
	Tavern, // Phase 6: sailors for hire; rolled from its own stream so older worlds keep their districts
	Shipyard, // Phase 7: repairs, ships and fittings; its own stream too
}

DISTRICT_CHANCE := [District]int {
	.Delivery_Service = 70,
	.Street_Vendor    = 60,
	.Dark_Alley       = 40,
	.Tavern           = TAVERN_CHANCE,
	.Shipyard         = SHIPYARD_CHANCE,
}

CARRY_MAX :: 3
OFFERS_MAX :: 3
DEADLINE_FACTOR :: 2 // turns allowed per league, as in the C++ game
VENDOR_LOT :: 5 // rations a lot at the street vendor
VENDOR_STOCK :: 10 // lots the vendor has each visit
REWARD_MAX :: 60_000

// Classic built its job text from word lists (kept in its database, never committed); these are new lists in the same
// shape: "please deliver this <adverb> <adjective> <object> to <name> the <trait> <profession>".
ADVERBS := [8]string{"carefully", "quietly", "quickly", "gently", "secretly", "promptly", "discreetly", "personally"}
ADJECTIVES := [8]string{"small", "sealed", "heavy", "fragile", "perfumed", "battered", "mysterious", "precious"}
OBJECTS := [8]string{"parcel", "letter", "crate", "casket", "bundle", "jar", "package", "chest"}
PEOPLE := [8]string{"Halek", "Mopu", "Kelima", "Pohak", "Lumi", "Hakepo", "Imala", "Opek"}
TRAITS := [8]string{"honest", "grumpy", "famous", "wealthy", "nervous", "jolly", "notorious", "elderly"}
PROFESSIONS := [8]string{"fishmonger", "cooper", "harbourmaster", "sailmaker", "priest", "widow", "merchant", "tailor"}

Delivery :: struct {
	from, to: int,
	reward:   int,
	due:      int, // the turn it is due by
	words:    [6]u8, // indices into the six word lists
}

generate_districts :: proc(g: ^Game) {
	r := rng_make(g.seed ~ 0xD1_57_41_C7)
	for i in 0 ..< g.n_islands {
		g.districts[i] = {}
		for d in District {
			if d == .Tavern || d == .Shipyard {continue}
			if rng_below(&r, 100) < DISTRICT_CHANCE[d] {g.districts[i] += {d}}
		}
	}
	t := rng_make(g.seed ~ 0x7A_BE_42_17)
	for i in 0 ..< g.n_islands {
		if rng_below(&t, 100) < DISTRICT_CHANCE[.Tavern] {g.districts[i] += {.Tavern}}
	}
	y := rng_make(g.seed ~ 0x5E_1F_A2_D9)
	for i in 0 ..< g.n_islands {
		if rng_below(&y, 100) < DISTRICT_CHANCE[.Shipyard] {g.districts[i] += {.Shipyard}}
	}
}

island_centre :: proc(g: ^Game, i: int) -> (x, y: f32) {
	return f32(g.islands[i].x) + 1, f32(g.islands[i].y) + 1
}

leagues_between :: proc(g: ^Game, a, b: int) -> int {
	ax, ay := island_centre(g, a)
	bx, by := island_centre(g, b)
	return int(math.round(math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))))
}

// Fresh offers at the docked island's delivery service (or none without one). Called on docking.
make_offers :: proc(g: ^Game) {
	g.n_offers = 0
	i := g.docked
	if i == NO_ISLAND || .Delivery_Service not_in g.districts[i] || g.n_islands < 2 {return}
	for g.n_offers < OFFERS_MAX {
		to := rng_below(&g.rng, g.n_islands - 1)
		if to >= i {to += 1}
		d := leagues_between(g, i, to)
		o := Delivery {
			from   = i,
			to     = to,
			reward = 10 + d + rng_below(&g.rng, 2 * d + 1),
			due    = g.turn + DEADLINE_FACTOR * d,
		}
		for k in 0 ..< 6 {o.words[k] = u8(rng_below(&g.rng, 8))}
		g.offers[g.n_offers] = o
		g.n_offers += 1
	}
}

accept_offer :: proc(g: ^Game, k: int) -> bool {
	if k < 0 || k >= g.n_offers || g.n_carried >= CARRY_MAX {return false}
	g.carried[g.n_carried] = g.offers[k]
	g.n_carried += 1
	g.islands[g.offers[k].to].charted = true // the sender tells you where it lies
	for j in k ..< g.n_offers - 1 {g.offers[j] = g.offers[j + 1]}
	g.n_offers -= 1
	return true
}

abandon :: proc(g: ^Game, k: int) -> bool {
	if k < 0 || k >= g.n_carried {return false}
	for j in k ..< g.n_carried - 1 {g.carried[j] = g.carried[j + 1]}
	g.n_carried -= 1
	return true
}

// What a delivery pays if handed over now: full by its due turn, half after.
pay_for :: proc(g: ^Game, d: Delivery) -> int {
	return g.turn <= d.due ? d.reward : d.reward / 2
}

// Hands over every delivery for the docked island. Returns how many and what they paid.
complete_deliveries :: proc(g: ^Game) -> (count, paid: int) {
	k := 0
	for k < g.n_carried {
		d := g.carried[k]
		if d.to != g.docked {
			k += 1
			continue
		}
		p := pay_for(g, d)
		g.money = min(g.money + p, MONEY_MAX)
		paid += p
		count += 1
		g.deliveries_made += 1
		abandon(g, k)
	}
	return
}

is_destination :: proc(g: ^Game, i: int) -> bool {
	for k in 0 ..< g.n_carried {
		if g.carried[k].to == i {return true}
	}
	for k in 0 ..< g.n_passengers {
		if g.passengers[k].to == i {return true}
	}
	return false
}

// "Please quietly deliver this sealed parcel to Mopu the grumpy cooper on Kalumo." into buf.
delivery_text :: proc(g: ^Game, d: Delivery, buf: []u8) -> string {
	w := d.words
	return bprint(
		buf,
		"Please ", ADVERBS[w[0] % 8], " deliver this ", ADJECTIVES[w[1] % 8], " ", OBJECTS[w[2] % 8], " to ",
		PEOPLE[w[3] % 8], " the ", TRAITS[w[4] % 8], " ", PROFESSIONS[w[5] % 8], " on ", island_name(g, d.to), ".",
	)
}

bprint :: proc(buf: []u8, parts: ..string) -> string {
	n := 0
	for p in parts {n += copy(buf[n:], p)}
	return string(buf[:n])
}

// The street vendor's price for a lot of five rations: cheaper than the market, about 0.6 grain.
vendor_price :: proc(g: ^Game, i: int) -> int {
	return max(1, int(math.round(0.6 * commodity_price(&g.markets[i], .Grain))))
}

buy_from_vendor :: proc(g: ^Game, lots: int) -> (count, cost: int) {
	i := g.docked
	if i == NO_ISLAND || .Street_Vendor not_in g.districts[i] {return}
	for count < lots && g.vendor_stock > 0 {
		p := vendor_price(g, i)
		if p > g.money || g.rations + VENDOR_LOT > RATIONS_MAX {break}
		g.money -= p
		g.rations += VENDOR_LOT
		g.vendor_stock -= 1
		cost += p
		count += 1
	}
	return
}
