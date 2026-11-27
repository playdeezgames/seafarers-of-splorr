package game

import "core:math"

// Save format, little-endian, fixed size. Bump SAVE_VERSION whenever the layout or the world generator changes (the
// world is rebuilt from the seed, so a new generator makes an old save describe a different sea). An older version is
// refused with Load_Error.Version and the page says so.
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
SAVE_VERSION :: 7
SAVE_V4_SIZE :: 82 + ISLAND_MAX * len(Commodity) * 4
SAVE_V5_SIZE :: SAVE_V4_SIZE + 2 * (1 + 12 * 3) + 1 + 2
SAVE_V6_SIZE :: SAVE_V5_SIZE + ISLAND_MAX * (2 + 2 * len(Good))
MEMBER_BYTES :: 15
ENTRY_BYTES :: 8
SAVE_SIZE :: SAVE_V6_SIZE + 1 + CREW_MAX * MEMBER_BYTES + 1 + CANDIDATES_MAX * MEMBER_BYTES + 2 + 1 + LOGBOOK_MAX * ENTRY_BYTES
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
	for good in Good {put_u16(buf[58 + 2 * int(good):], u16(g.cargo[good]))}
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
		for good in Good {put_u16(buf[at6 + 2 + 2 * int(good):], u16(clamp(seen.price[good], 0, PRICE_MAX)))}
		at6 += 2 + 2 * len(Good)
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
	sizes := [8]int{0, 0, SAVE_V2_SIZE, SAVE_V3_SIZE, SAVE_V4_SIZE, SAVE_V5_SIZE, SAVE_V6_SIZE, SAVE_SIZE}
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
				if i >= t.n_islands || turn > int(turn_saved) {return .Range}
				t.seen[i].turn = turn
			}
			for good in Good {
				p := int(get_u16(data[at + 2 + 2 * int(good):]))
				if p > PRICE_MAX {return .Range}
				traded := i < t.n_islands && good in t.trades[i]
				t.seen[i].price[good] = traded && turn != NOT_SEEN ? p : 0 // only what the island trades
			}
			at += 2 + 2 * len(Good)
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
	if version < 4 {
		t.money = START_MONEY
	} else {
		for good in Good {
			n := int(get_u16(data[58 + 2 * int(good):]))
			if n > CARGO_MAX {return .Range}
			t.cargo[good] = n
		}
		if hold_used(t) > HOLD_TONS {return .Range}
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
