package game

import "core:math"

// Save format, little-endian, fixed size. Bump SAVE_VERSION whenever the layout or the world generator changes (the
// world is rebuilt from the seed, so a new generator makes an old save describe a different sea). An older version is
// refused with Load_Error.Version and the page says so.
//
// Version 11 (Phase 9, weather) is version 10 followed by:
//  u64         the weather's generator
//  u16         the direction the wind blows from (degrees)
//  u8          the wind's force
//  u8, 6 x s   storms: count, then six slots
//  u16         rats aboard
// A storm is 12 bytes: x f32, y f32, radius in tenths of a tile u8, turns left u16, seen u8.
// Older versions load with the voyage's first weather, no storms and no rats.
//
// Version 10 (Phase 8, things at sea) is version 9 followed by:
//  u8 x 4      the encounter: kind (0 for none), state, health, health at the start
//  u16         your fighters' health when it began
//  u8          flags: 1 parleyed, 2 friendly, 4 hostile
//  u16 x 3     sea goods aboard: whale oil, pearls, coral
// The save layout before this keeps the first twelve goods only. Older versions load with nothing met and no sea goods.
//
// Version 9 (Phase 7, the shipyard) is version 8 followed by:
//  u8          ship type
//  u8 x 4      fittings, by Fitting
//  u16         hull points
//  u8, 2 x p   passengers asking for passage at the docked island: count, then two slots
//  u8, 3 x p   passengers aboard: count, then three slots
// A passenger is 10 bytes: name seed u32, from u8, to u8, fare u16, due turn u16.
// Older versions load with a sloop, no fittings and a sound hull.
//
// Version 8 (piloting) is version 7 followed by one byte: the island Head for is piloting to, 255 for none. Older
// versions load with no course.
//
// Version 7 (Phase 6, crew) is version 6 followed by:
//  u8, 7 x member     the crew: count (1 ..= 7, the captain first), then seven slots
//  u8, 3 x member     sailors at the docked island's tavern: count, then three slots
//  u16                turns since wages were paid
//  u8, 64 x entry     the captain's log: count, then 64 slots
// A member is 15 bytes: name seed u32, profession u8, eight skills u8, hit points u8 (the captain's is the health
// above), wage u8. A log entry is 8 bytes: turn u16, kind u8, island u8 (255 at sea), value u32.
// Older versions load with a captain of base skills and no crew (so nothing changes for them), and an empty log.
//
// Version 6 (the price book) is version 5 followed by, for each of the 40 island slots: the turn its prices were
// last seen (u16, 0xFFFF for never) and the price it asked for each of the 12 goods (u16, 0 if it does not trade it).
// Older versions load with an empty book (the docked island's prices are recorded on load).
//
// Version 5 (Phase 4) is version 4 followed by:
// 1042  u8, 3 x delivery    offers at the docked island: count, then three slots
// 1079  u8, 3 x delivery    deliveries carried: count, then three slots
// 1116  u8                  street vendor lots left
// 1117  u16                 deliveries made
// A delivery is 12 bytes: from u8, to u8, reward u16, due turn u16, six word indices u8.
// Older versions load with nothing offered or carried and a full vendor.
//
// Version 4 (Phase 3) is version 3 followed by:
// 58  u16 x 12              cargo, by Good
// 82  u16 x 40 x 6 x 2      markets: for each island slot, for each commodity, supply then demand (thousandths)
// Versions 2 and 3 still load: the purse is set to the starting money (no voyage could earn any before Phase 3), the
// hold is empty and the markets are at their usual levels.
//
// Version 3 (Phase 2) is version 2 followed by:
// 44  u32    money
// 48  u32    rations
// 52  u8     satiety
// 53  u8     health
// 54  u16    port fouling (ten-thousandths)
// 56  u16    starboard fouling
// A version 2 save (Phase 1, same world generator) still loads, with the Phase 2 starting values.
//
// Version 2 (Phase 1):
//  0  "SOS"  magic
//  3  u8     version
//  4  u64    world seed
// 12  u64    rng state
// 20  u32    turn
// 24  f32    ship x (tiles)
// 28  f32    ship y (tiles)
// 32  u16    heading (degrees)
// 34  u8     speed (percent)
// 35  u8     docked island, 255 at sea
// 36  u64    charted islands, bit i for island i
SAVE_VERSION :: 11
SAVE_V4_SIZE :: 82 + ISLAND_MAX * len(Commodity) * 4
SAVE_V5_SIZE :: SAVE_V4_SIZE + 2 * (1 + 12 * 3) + 1 + 2
SAVE_V6_SIZE :: SAVE_V5_SIZE + ISLAND_MAX * (2 + 2 * LAND_GOODS)
MEMBER_BYTES :: 15
ENTRY_BYTES :: 8
SAVE_V7_SIZE :: SAVE_V6_SIZE + 1 + CREW_MAX * MEMBER_BYTES + 1 + CANDIDATES_MAX * MEMBER_BYTES + 2 + 1 + LOGBOOK_MAX * ENTRY_BYTES
SAVE_V8_SIZE :: SAVE_V7_SIZE + 1
PASSENGER_BYTES :: 10
SAVE_V9_SIZE :: SAVE_V8_SIZE + 1 + len(Fitting) + 2 + 1 + FARE_OFFERS_MAX * PASSENGER_BYTES + 1 + CABINS_MAX * PASSENGER_BYTES
SEA_GOODS :: len(Good) - LAND_GOODS
SAVE_V10_SIZE :: SAVE_V9_SIZE + 4 + 2 + 1 + 2 * SEA_GOODS
STORM_BYTES :: 12
SAVE_SIZE :: SAVE_V10_SIZE + 8 + 2 + 1 + 1 + STORMS_MAX * STORM_BYTES + 2
NOT_SEEN :: 0xFFFF
PRICE_MAX :: 60_000
SAVE_V3_SIZE :: 58
SAVE_V2_SIZE :: 44
NOT_DOCKED :: 255

Load_Error :: enum u8 {
	None,
	Size,
	Magic,
	Version,
	Range,
}

#assert(ISLAND_MAX <= 64)

save_encode :: proc(g: ^Game, buf: ^[SAVE_SIZE]u8) {
	buf[0], buf[1], buf[2], buf[3] = 'S', 'O', 'S', SAVE_VERSION
	put_u64(buf[4:], g.seed)
	put_u64(buf[12:], g.rng.state)
	put_u32(buf[20:], u32(g.turn))
	put_u32(buf[24:], transmute(u32)g.ship.x)
	put_u32(buf[28:], transmute(u32)g.ship.y)
	put_u16(buf[32:], u16(g.ship.heading))
	buf[34] = u8(g.ship.speed)
	buf[35] = g.docked == NO_ISLAND ? NOT_DOCKED : u8(g.docked)
	charted: u64
	for i in 0 ..< g.n_islands {
		if g.islands[i].charted {charted |= 1 << uint(i)}
	}
	put_u64(buf[36:], charted)
	put_u32(buf[44:], u32(g.money))
	put_u32(buf[48:], u32(g.rations))
	buf[52] = u8(g.satiety)
	buf[53] = u8(g.health)
	put_u16(buf[54:], u16(g.foul[.Port]))
	put_u16(buf[56:], u16(g.foul[.Starboard]))
	for good in Good.Flour ..= Good.Pepper {put_u16(buf[58 + 2 * int(good):], u16(g.cargo[good]))}
	at5 := SAVE_V4_SIZE
	put_deliveries(buf[at5:], g.offers[:g.n_offers])
	at5 += 1 + 12 * 3
	put_deliveries(buf[at5:], g.carried[:g.n_carried])
	at5 += 1 + 12 * 3
	buf[at5] = u8(g.vendor_stock)
	put_u16(buf[at5 + 1:], u16(min(g.deliveries_made, 65535)))
	at6 := SAVE_V5_SIZE
	for i in 0 ..< ISLAND_MAX {
		seen := g.seen[i]
		put_u16(buf[at6:], seen.turn == NEVER_SEEN || i >= g.n_islands ? NOT_SEEN : u16(seen.turn))
		for good in Good.Flour ..= Good.Pepper {put_u16(buf[at6 + 2 + 2 * int(good):], u16(clamp(seen.price[good], 0, PRICE_MAX)))}
		at6 += 2 + 2 * LAND_GOODS
	}
	at7 := SAVE_V6_SIZE
	buf[at7] = u8(g.n_crew)
	for k in 0 ..< g.n_crew {
		m := g.crew[k]
		if k == 0 {m.hp = g.health}
		put_member(buf[at7 + 1 + MEMBER_BYTES * k:], m)
	}
	at7 += 1 + CREW_MAX * MEMBER_BYTES
	buf[at7] = u8(g.n_candidates)
	for k in 0 ..< g.n_candidates {put_member(buf[at7 + 1 + MEMBER_BYTES * k:], g.candidates[k])}
	at7 += 1 + CANDIDATES_MAX * MEMBER_BYTES
	put_u16(buf[at7:], u16(g.wage_turns))
	at7 += 2
	buf[at7] = u8(g.n_logbook)
	for k in 0 ..< g.n_logbook {
		e := g.logbook[k]
		o := buf[at7 + 1 + ENTRY_BYTES * k:]
		put_u16(o, u16(e.turn))
		o[2] = u8(e.kind)
		o[3] = e.island == NO_ISLAND ? NOT_DOCKED : u8(e.island)
		put_u32(o[4:], u32(e.value))
	}
	buf[SAVE_V7_SIZE] = g.course == NO_ISLAND ? NOT_DOCKED : u8(g.course)
	at9 := SAVE_V8_SIZE
	buf[at9] = u8(g.ship_type)
	for f in Fitting {buf[at9 + 1 + int(f)] = u8(g.fitted[f])}
	at9 += 1 + len(Fitting)
	put_u16(buf[at9:], u16(g.hull))
	at9 += 2
	put_passengers(buf[at9:], g.fare_offers[:g.n_fare_offers])
	at9 += 1 + FARE_OFFERS_MAX * PASSENGER_BYTES
	put_passengers(buf[at9:], g.passengers[:g.n_passengers])
	at10 := SAVE_V9_SIZE
	f := g.foe
	buf[at10], buf[at10 + 1], buf[at10 + 2], buf[at10 + 3] = u8(f.kind), u8(f.state), u8(f.hp), u8(f.hp_max)
	put_u16(buf[at10 + 4:], u16(f.strength))
	buf[at10 + 6] = (f.parleyed ? 1 : 0) | (f.friendly ? 2 : 0) | (f.hostile ? 4 : 0)
	for k in 0 ..< SEA_GOODS {put_u16(buf[at10 + 7 + 2 * k:], u16(g.cargo[Good(LAND_GOODS + k)]))}
	at11 := SAVE_V10_SIZE
	put_u64(buf[at11:], g.weather.state)
	put_u16(buf[at11 + 8:], u16(g.wind_dir))
	buf[at11 + 10] = u8(g.wind_force)
	buf[at11 + 11] = u8(g.n_storms)
	at11 += 12
	for k in 0 ..< g.n_storms {
		st := g.storms[k]
		o := buf[at11 + STORM_BYTES * k:]
		put_u32(o, transmute(u32)st.x)
		put_u32(o[4:], transmute(u32)st.y)
		o[8] = u8(math.round(st.radius * 10))
		put_u16(o[9:], u16(st.turns))
		o[11] = st.seen ? 1 : 0
	}
	put_u16(buf[at11 + STORMS_MAX * STORM_BYTES:], u16(g.rats))
	at := 82
	for i in 0 ..< ISLAND_MAX {
		for c in Commodity {
			put_u16(buf[at:], u16(g.markets[i].supply[c]))
			put_u16(buf[at + 2:], u16(g.markets[i].demand[c]))
			at += 4
		}
	}
}

// Restores a voyage into g (on the title screen, ready to continue). On any error g is left as it was.
save_decode :: proc(g: ^Game, data: []u8) -> Load_Error {
	if len(data) < 4 {return .Size}
	if data[0] != 'S' || data[1] != 'O' || data[2] != 'S' {return .Magic}
	version := data[3]
	if version < 2 || version > SAVE_VERSION {return .Version} // before the size: versions differ in size
	sizes := [12]int{0, 0, SAVE_V2_SIZE, SAVE_V3_SIZE, SAVE_V4_SIZE, SAVE_V5_SIZE, SAVE_V6_SIZE, SAVE_V7_SIZE, SAVE_V8_SIZE, SAVE_V9_SIZE, SAVE_V10_SIZE, SAVE_SIZE}
	if len(data) != sizes[version] {return .Size}
	turn := get_u32(data[20:])
	turn_saved := turn
	x := transmute(f32)get_u32(data[24:])
	y := transmute(f32)get_u32(data[28:])
	heading := int(get_u16(data[32:]))
	speed := int(data[34])
	if turn >= TURN_LIMIT {return .Range} // a voyage at the limit has ended and is not saved
	if !in_world(x) || !in_world(y) {return .Range}
	if heading >= 360 || speed > 100 {return .Range}

	// The rest needs the world, so build it aside and only copy it over when everything checks out.
	t := new(Game)
	defer free(t)
	start_world(t, get_u64(data[4:]))
	docked := int(data[35])
	charted := get_u64(data[36:])
	if docked != NOT_DOCKED && docked >= t.n_islands {return .Range}
	if t.n_islands < 64 && charted >> uint(t.n_islands) != 0 {return .Range}
	if is_land(t, int(x), int(y)) {return .Range}
	t.ship = {x = x, y = y, heading = heading, speed = speed}
	t.docked = docked == NOT_DOCKED ? NO_ISLAND : docked
	if t.docked != NO_ISLAND && island_distance(t, t.docked, x, y) > DOCK_RANGE {return .Range}
	for i in 0 ..< t.n_islands {t.islands[i].charted = charted & (1 << uint(i)) != 0}

	if version >= 3 {
		money, rations := get_u32(data[44:]), get_u32(data[48:])
		satiety, health := int(data[52]), int(data[53])
		port, starboard := int(get_u16(data[54:])), int(get_u16(data[56:]))
		if money > 1_000_000_000 || rations > RATIONS_MAX {return .Range}
		if satiety > STAT_MAX || health > STAT_MAX || health == 0 {return .Range}
		if port > FOUL_MAX || starboard > FOUL_MAX {return .Range}
		t.money, t.rations, t.satiety, t.health = int(money), int(rations), satiety, health
		t.foul = {.Port = port, .Starboard = starboard}
	}
	if version >= 5 {
		at := SAVE_V4_SIZE
		ok: bool
		if t.n_offers, ok = get_deliveries(t, data[at:], t.offers[:]); !ok {return .Range}
		at += 1 + 12 * 3
		if t.n_carried, ok = get_deliveries(t, data[at:], t.carried[:]); !ok {return .Range}
		at += 1 + 12 * 3
		for k in 0 ..< t.n_offers {
			if t.offers[k].from != t.docked {return .Range} // offers only exist at the island you are docked at
		}
		t.vendor_stock = int(data[at])
		if t.vendor_stock > VENDOR_STOCK {return .Range}
		t.deliveries_made = int(get_u16(data[at + 1:]))
	} else {
		t.n_offers = 0
	}
	if version >= 6 {
		at := SAVE_V5_SIZE
		for i in 0 ..< ISLAND_MAX {
			turn := int(get_u16(data[at:]))
			if turn == NOT_SEEN {
				t.seen[i] = {turn = NEVER_SEEN}
			} else {
				if i >= t.n_islands {return .Range}
				// Builds before the fix on November 27, 2026 stamped the home port of a second voyage in one sitting
				// with the previous voyage's turn; read a seen turn from the future as seen now.
				t.seen[i].turn = min(turn, int(turn_saved))
			}
			for good in Good.Flour ..= Good.Pepper {
				p := int(get_u16(data[at + 2 + 2 * int(good):]))
				if p > PRICE_MAX {return .Range}
				traded := i < t.n_islands && good in t.trades[i]
				t.seen[i].price[good] = traded && turn != NOT_SEEN ? p : 0 // only what the island trades
			}
			at += 2 + 2 * LAND_GOODS
		}
	}
	if version >= 7 {
		at := SAVE_V6_SIZE
		n := int(data[at])
		if n < 1 || n > CREW_MAX {return .Range}
		for k in 0 ..< n {
			m, ok := get_member(data[at + 1 + MEMBER_BYTES * k:])
			if !ok {return .Range}
			if k == 0 {m.hp, m.wage = STAT_MAX, 0}
			t.crew[k] = m
		}
		t.n_crew = n
		at += 1 + CREW_MAX * MEMBER_BYTES
		n = int(data[at])
		if n > CANDIDATES_MAX {return .Range}
		if n > 0 && (t.docked == NO_ISLAND || .Tavern not_in t.districts[t.docked]) {return .Range}
		for k in 0 ..< n {
			m, ok := get_member(data[at + 1 + MEMBER_BYTES * k:])
			if !ok {return .Range}
			t.candidates[k] = m
		}
		t.n_candidates = n
		at += 1 + CANDIDATES_MAX * MEMBER_BYTES
		t.wage_turns = int(get_u16(data[at:]))
		if t.wage_turns > TURN_LIMIT {return .Range}
		at += 2
		n = int(data[at])
		if n > LOGBOOK_MAX {return .Range}
		for k in 0 ..< n {
			o := data[at + 1 + ENTRY_BYTES * k:]
			e := Log_Entry {
				turn   = int(get_u16(o)),
				island = o[3] == NOT_DOCKED ? NO_ISLAND : int(o[3]),
				value  = int(get_u32(o[4:])),
			}
			if e.turn > int(turn_saved) || o[2] > u8(max(Log_Kind)) || (e.island != NO_ISLAND && e.island >= t.n_islands) {return .Range}
			e.kind = Log_Kind(o[2])
			t.logbook[k] = e
		}
		t.n_logbook = n
	}
	if version >= 8 {
		c := data[SAVE_V7_SIZE]
		if c != NOT_DOCKED {
			if int(c) >= t.n_islands || !t.islands[c].charted || t.docked != NO_ISLAND {return .Range}
			t.course = int(c)
		}
	}
	if version >= 9 {
		at := SAVE_V8_SIZE
		if data[at] > u8(max(Ship_Type)) {return .Range}
		t.ship_type = Ship_Type(data[at])
		for f in Fitting {
			n := int(data[at + 1 + int(f)])
			if n > FITTINGS[f].most {return .Range}
			t.fitted[f] = n
		}
		at += 1 + len(Fitting)
		t.hull = int(get_u16(data[at:]))
		if t.hull < 1 || t.hull > hull_max(t) {return .Range}
		at += 2
		ok: bool
		if t.n_fare_offers, ok = get_passengers(t, data[at:], t.fare_offers[:]); !ok {return .Range}
		for k in 0 ..< t.n_fare_offers {
			if t.fare_offers[k].from != t.docked {return .Range}
		}
		at += 1 + FARE_OFFERS_MAX * PASSENGER_BYTES
		if t.n_passengers, ok = get_passengers(t, data[at:], t.passengers[:]); !ok {return .Range}
		if t.n_passengers > t.fitted[.Cabin] {return .Range}
	} else {
		t.hull = hull_max(t)
	}
	if version < 4 {
		t.money = START_MONEY
	} else {
		for good in Good.Flour ..= Good.Pepper {
			n := int(get_u16(data[58 + 2 * int(good):]))
			if n > CARGO_MAX {return .Range}
			t.cargo[good] = n
		}
		at := 82
		for i in 0 ..< ISLAND_MAX {
			for c in Commodity {
				sup, dem := int(get_u16(data[at:])), int(get_u16(data[at + 2:]))
				at += 4
				if i >= t.n_islands {
					if sup != 0 || dem != 0 {return .Range}
					continue
				}
				if sup < MARKET_MIN || sup > MARKET_MAX || dem < MARKET_MIN || dem > MARKET_MAX {return .Range}
				t.markets[i].supply[c], t.markets[i].demand[c] = sup, dem
			}
		}
	}
	if version >= 10 {
		at := SAVE_V9_SIZE
		if data[at] > u8(max(Foe_Kind)) || data[at + 1] > u8(max(Foe_State)) || data[at + 6] > 7 {return .Range}
		f := Encounter {
			kind     = Foe_Kind(data[at]),
			state    = Foe_State(data[at + 1]),
			hp       = int(data[at + 2]),
			hp_max   = int(data[at + 3]),
			strength = int(get_u16(data[at + 4:])),
			parleyed = data[at + 6] & 1 != 0,
			friendly = data[at + 6] & 2 != 0,
			hostile  = data[at + 6] & 4 != 0,
		}
		if f.kind != .None {
			if t.docked != NO_ISLAND || f.hp < 1 || f.hp > f.hp_max {return .Range}
			if f.state == .Trading && f.kind != .Merfolk {return .Range}
			t.foe = f
			t.sub = .Encounter
		}
		for k in 0 ..< SEA_GOODS {
			n := int(get_u16(data[at + 7 + 2 * k:]))
			if n > CARGO_MAX {return .Range}
			t.cargo[Good(LAND_GOODS + k)] = n
		}
	}
	if version >= 11 {
		at := SAVE_V10_SIZE
		t.weather.state = get_u64(data[at:])
		t.wind_dir = int(get_u16(data[at + 8:]))
		if t.wind_dir >= 360 || data[at + 10] > u8(max(Wind_Force)) || data[at + 11] > STORMS_MAX {return .Range}
		t.wind_force = Wind_Force(data[at + 10])
		t.n_storms = int(data[at + 11])
		at += 12
		for k in 0 ..< t.n_storms {
			o := data[at + STORM_BYTES * k:]
			st := Storm {
				x      = transmute(f32)get_u32(o),
				y      = transmute(f32)get_u32(o[4:]),
				radius = f32(o[8]) / 10,
				turns  = int(get_u16(o[9:])),
				seen   = o[11] == 1,
			}
			if !in_world(st.x) || !in_world(st.y) || o[8] < 15 || o[8] > 40 || st.turns < 1 || st.turns > 150 || o[11] > 1 {return .Range}
			t.storms[k] = st
		}
		t.rats = int(get_u16(data[at + STORMS_MAX * STORM_BYTES:]))
		if t.rats > RATS_MAX {return .Range}
	}
	if hold_used(t) > hold_tons(t) {return .Range} // after the ship and the cargo are both read
	t.rng.state = get_u64(data[12:])
	t.turn = int(turn)
	t.next_seed = g.next_seed
	t.muted = g.muted
	t.best, t.has_best = g.best, g.has_best
	t.log, t.log_len = g.log, g.log_len
	if version < 6 {
		for i in 0 ..< ISLAND_MAX {t.seen[i] = {turn = NEVER_SEEN}}
		record_prices(t)
	}
	t.has_voyage = true
	t.screen = .Title
	g^ = t^
	return .None
}

in_world :: proc(v: f32) -> bool {
	return !math.is_nan(v) && !math.is_inf(v) && v >= 0 && v < WORLD_SIZE
}

put_u16 :: proc(b: []u8, v: u16) {
	b[0], b[1] = u8(v), u8(v >> 8)
}
put_u32 :: proc(b: []u8, v: u32) {
	for i in 0 ..< 4 {b[i] = u8(v >> (8 * uint(i)))}
}
put_u64 :: proc(b: []u8, v: u64) {
	for i in 0 ..< 8 {b[i] = u8(v >> (8 * uint(i)))}
}
get_u16 :: proc(b: []u8) -> u16 {
	return u16(b[0]) | u16(b[1]) << 8
}
get_u32 :: proc(b: []u8) -> (v: u32) {
	for i in 0 ..< 4 {v |= u32(b[i]) << (8 * uint(i))}
	return
}
get_u64 :: proc(b: []u8) -> (v: u64) {
	for i in 0 ..< 8 {v |= u64(b[i]) << (8 * uint(i))}
	return
}

put_passengers :: proc(b: []u8, ps: []Passenger) {
	b[0] = u8(len(ps))
	for p, k in ps {
		o := b[1 + PASSENGER_BYTES * k:]
		put_u32(o, p.name_seed)
		o[4], o[5] = u8(p.from), u8(p.to)
		put_u16(o[6:], u16(p.fare))
		put_u16(o[8:], u16(p.due))
	}
}

get_passengers :: proc(t: ^Game, b: []u8, out: []Passenger) -> (n: int, ok: bool) {
	n = int(b[0])
	if n > len(out) {return 0, false}
	for k in 0 ..< n {
		o := b[1 + PASSENGER_BYTES * k:]
		p := Passenger {
			name_seed = get_u32(o),
			from      = int(o[4]),
			to        = int(o[5]),
			fare      = int(get_u16(o[6:])),
			due       = int(get_u16(o[8:])),
		}
		if p.from >= t.n_islands || p.to >= t.n_islands || p.from == p.to || p.fare > REWARD_MAX {return 0, false}
		out[k] = p
	}
	return n, true
}

put_member :: proc(b: []u8, m: Member) {
	put_u32(b, m.name_seed)
	b[4] = u8(m.profession)
	for s in Skill {b[5 + int(s)] = u8(m.skills[s])}
	b[13] = u8(m.hp)
	b[14] = u8(m.wage)
}

get_member :: proc(b: []u8) -> (m: Member, ok: bool) {
	m.name_seed = get_u32(b)
	if b[4] > u8(max(Profession)) {return}
	m.profession = Profession(b[4])
	for s in Skill {
		if b[5 + int(s)] > 100 {return}
		m.skills[s] = int(b[5 + int(s)])
	}
	m.hp, m.wage = int(b[13]), int(b[14])
	if m.hp < 1 || m.hp > STAT_MAX || m.wage > WAGE_MAX {return}
	return m, true
}

put_deliveries :: proc(b: []u8, ds: []Delivery) {
	b[0] = u8(len(ds))
	for d, k in ds {
		o := b[1 + 12 * k:]
		o[0], o[1] = u8(d.from), u8(d.to)
		put_u16(o[2:], u16(d.reward))
		put_u16(o[4:], u16(d.due))
		for w in 0 ..< 6 {o[6 + w] = d.words[w]}
	}
}

// Reads a count and up to len(out) deliveries, checking every field against the world in t.
get_deliveries :: proc(t: ^Game, b: []u8, out: []Delivery) -> (n: int, ok: bool) {
	n = int(b[0])
	if n > len(out) {return 0, false}
	for k in 0 ..< n {
		o := b[1 + 12 * k:]
		d := Delivery {
			from   = int(o[0]),
			to     = int(o[1]),
			reward = int(get_u16(o[2:])),
			due    = int(get_u16(o[4:])),
		}
		if d.from >= t.n_islands || d.to >= t.n_islands || d.from == d.to || d.reward > REWARD_MAX {return 0, false}
		for w in 0 ..< 6 {
			if o[6 + w] >= 8 {return 0, false}
			d.words[w] = o[6 + w]
		}
		out[k] = d
	}
	return n, true
}
