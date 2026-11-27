package game

// The shipyard (Phase 7). The user chose ship types and fittings, approved Claude's draft fittings and prices, chose
// that nothing damages the hull until fights (Phase 8) and storms (Phase 9), and passengers that work like deliveries
// (November 27, 2026). The C++ game had a Raft and a Junk (speed 1.25); these three are new, with its Junk kept.
//
// Some islands have a shipyard. There you can repair the hull, buy another ship (your own is taken in part
// exchange at half its price, and your fittings move across), and buy fittings. Careening moved into the docked Ship
// menu with them, to keep the docked menu within nine items.

Ship_Type :: enum u8 {
	Sloop,
	Junk,
	Brig,
}

Ship_Info :: struct {
	name:  string,
	hold:  int, // tons
	hull:  int, // points
	speed: f32, // times the sloop's
	price: int,
}

SHIPS := [Ship_Type]Ship_Info {
	.Sloop = {"Sloop", 50, 100, 1.0, 600},
	.Junk  = {"Junk", 60, 120, 1.25, 1500},
	.Brig  = {"Brig", 100, 200, 0.9, 3000},
}

Fitting :: enum u8 {
	Extra_Hold,
	Copper,
	Cabin,
	Timbers,
}

Fitting_Info :: struct {
	name:  string,
	short: string, // for the menu
	price: int,
	most:  int,
}

FITTINGS := [Fitting]Fitting_Info {
	.Extra_Hold = {"Extra hold", "Extra hold", 400, 2},
	.Copper     = {"Copper sheathing", "Copper", 600, 1},
	.Cabin      = {"Passenger cabin", "Cabin", 300, 3},
	.Timbers    = {"Stout timbers", "Timbers", 500, 1},
}

EXTRA_HOLD_TONS :: 25
TIMBERS_HULL :: 50
REPAIR_COST :: 2 // per hull point
SHIPYARD_CHANCE :: 40
FARE_OFFERS_MAX :: 2
CABINS_MAX :: 3 // FITTINGS[.Cabin].most
TRADE_IN_PERCENT :: 50

hold_tons :: proc(g: ^Game) -> int {
	return SHIPS[g.ship_type].hold + EXTRA_HOLD_TONS * g.fitted[.Extra_Hold]
}

hull_max :: proc(g: ^Game) -> int {
	return SHIPS[g.ship_type].hull + TIMBERS_HULL * g.fitted[.Timbers]
}

ship_speed :: proc(g: ^Game) -> f32 {
	return SHIPS[g.ship_type].speed
}

trade_in :: proc(g: ^Game) -> int {
	return SHIPS[g.ship_type].price * TRADE_IN_PERCENT / 100
}

// What a ship costs after the part exchange of your own.
ship_cost :: proc(g: ^Game, s: Ship_Type) -> int {
	return max(0, SHIPS[s].price - trade_in(g))
}

repair_cost :: proc(g: ^Game) -> int {
	return (hull_max(g) - g.hull) * REPAIR_COST
}

at_shipyard :: proc(g: ^Game) -> bool {
	return g.docked != NO_ISLAND && .Shipyard in g.districts[g.docked]
}

// Repairs as much of the hull as the purse covers. Returns the points mended.
repair :: proc(g: ^Game) -> int {
	if !at_shipyard(g) {return 0}
	n := min(hull_max(g) - g.hull, g.money / REPAIR_COST)
	g.hull += n
	g.money -= n * REPAIR_COST
	return n
}

Refusal :: enum u8 {
	None,
	No_Shipyard,
	Money,
	Same, // that ship is yours already
	Hold, // the cargo would not fit
	Most, // no more of that fitting
}

buy_ship :: proc(g: ^Game, s: Ship_Type) -> Refusal {
	if !at_shipyard(g) {return .No_Shipyard}
	if s == g.ship_type {return .Same}
	cost := ship_cost(g, s)
	if cost > g.money {return .Money}
	if hold_used(g) > SHIPS[s].hold + EXTRA_HOLD_TONS * g.fitted[.Extra_Hold] {return .Hold}
	g.money -= cost
	g.ship_type = s
	g.hull = hull_max(g)
	note(g, .New_Ship, g.docked, int(s))
	return .None
}

fit :: proc(g: ^Game, f: Fitting) -> Refusal {
	if !at_shipyard(g) {return .No_Shipyard}
	if g.fitted[f] >= FITTINGS[f].most {return .Most}
	if FITTINGS[f].price > g.money {return .Money}
	g.money -= FITTINGS[f].price
	g.fitted[f] += 1
	if f == .Timbers {g.hull += TIMBERS_HULL}
	return .None
}

// Damage to the hull, from fights and storms in later phases. At 0 the ship goes down and the voyage ends.
damage_hull :: proc(g: ^Game, n: int) {
	g.hull = max(g.hull - n, 0)
	if g.hull == 0 {end_voyage(g, .Sank)}
}

// Passengers: offered at the delivery service when a cabin is free, with a fare and a deadline like a delivery, and
// they eat a ration a turn like the crew.
Passenger :: struct {
	name_seed: u32,
	from, to:  int,
	fare:      int,
	due:       int,
}

make_fare_offers :: proc(g: ^Game) {
	g.n_fare_offers = 0
	i := g.docked
	if i == NO_ISLAND || .Delivery_Service not_in g.districts[i] || g.n_islands < 2 {return}
	free := g.fitted[.Cabin] - g.n_passengers
	for g.n_fare_offers < min(FARE_OFFERS_MAX, free) {
		to := rng_below(&g.rng, g.n_islands - 1)
		if to >= i {to += 1}
		d := leagues_between(g, i, to)
		g.fare_offers[g.n_fare_offers] = {
			name_seed = new_name_seed(&g.rng),
			from      = i,
			to        = to,
			fare      = 20 + 2 * d + rng_below(&g.rng, 2 * d + 1),
			due       = g.turn + DEADLINE_FACTOR * d,
		}
		g.n_fare_offers += 1
	}
}

take_fare :: proc(g: ^Game, k: int) -> bool {
	if k < 0 || k >= g.n_fare_offers || g.n_passengers >= g.fitted[.Cabin] {return false}
	g.passengers[g.n_passengers] = g.fare_offers[k]
	g.n_passengers += 1
	g.islands[g.fare_offers[k].to].charted = true
	for j in k ..< g.n_fare_offers - 1 {g.fare_offers[j] = g.fare_offers[j + 1]}
	g.n_fare_offers -= 1
	return true
}

put_ashore :: proc(g: ^Game, k: int) -> bool {
	if k < 0 || k >= g.n_passengers || g.docked == NO_ISLAND {return false}
	for j in k ..< g.n_passengers - 1 {g.passengers[j] = g.passengers[j + 1]}
	g.n_passengers -= 1
	return true
}

fare_for :: proc(g: ^Game, p: Passenger) -> int {
	return g.turn <= p.due ? p.fare : p.fare / 2
}

// Lands every passenger bound for the docked island. Returns how many and what they paid.
land_passengers :: proc(g: ^Game) -> (count, paid: int) {
	k := 0
	for k < g.n_passengers {
		p := g.passengers[k]
		if p.to != g.docked {
			k += 1
			continue
		}
		f := fare_for(g, p)
		g.money = min(g.money + f, MONEY_MAX)
		paid += f
		count += 1
		for j in k ..< g.n_passengers - 1 {g.passengers[j] = g.passengers[j + 1]}
		g.n_passengers -= 1
	}
	return
}
