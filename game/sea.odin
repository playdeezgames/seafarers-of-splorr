package game

// Things at sea and combat (Phase 8). The user chose encounters sprung while sailing, about one every fifty turns under
// way; fights in menu rounds; a lost fight costs hull, crew and cargo; and merfolk who trade pearls and coral
// (November 27, 2026).
//
// An encounter stops the ship. A Spot roll sees it coming, and then you may steer away or close. Each round you pick
// from a short menu; your crew's Melee (Track for whales) and the foe's attacks are rolled, and the foe acts after you.
// Pirates who beat your crew (your fighters fall below 60% of their health at the start) take half your money and
// cargo and leave. A monster's blows fall on the hull. The voyage ends only if the ship sinks or the captain falls.

ENCOUNTER_CHANCE :: 2 // percent a turn under way: about one every fifty turns
BEATEN_PERCENT :: 60

Foe_Kind :: enum u8 {
	None,
	Pirates,
	Monster,
	Whale,
	Merfolk,
}

Foe_Info :: struct {
	name:        string,
	hp_min:      int,
	hp_spread:   int,
	attacks:     int, // a round
	chance:      int, // percent each attack lands
	hull_lo:     int, // hull damage a landed attack (0 for none)
	hull_hi:     int,
	wound_lo:    int, // a crew member's wound a landed attack (0 for none)
	wound_hi:    int,
	weight:      int, // how often it is the one met
}

FOES := [Foe_Kind]Foe_Info {
	.None    = {},
	.Pirates = {"Pirates", 45, 41, 4, 45, 1, 4, 6, 15, 35},
	.Monster = {"A sea monster", 50, 41, 1, 65, 6, 14, 0, 0, 20},
	.Whale   = {"A whale", 30, 21, 1, 35, 4, 10, 0, 0, 25},
	.Merfolk = {"Merfolk", 30, 21, 3, 40, 0, 0, 5, 12, 20},
}

Foe_State :: enum u8 {
	Distant, // seen coming: steer away or close
	Close, // in reach: the round menu
	Trading, // merfolk, trading
}

Encounter :: struct {
	kind:     Foe_Kind,
	state:    Foe_State,
	hp:       int,
	hp_max:   int,
	strength: int, // your fighters' health when it began
	parleyed: bool, // merfolk: the parley is spent (and Bargain applied if it went well)
	friendly: bool, // merfolk: the parley went well
	hostile:  bool, // merfolk: fighting
}

is_sea_good :: proc(good: Good) -> bool {return good >= .Whale_Oil}

// Rolled once a turn under way, from g.rng. True when an encounter begins.
maybe_encounter :: proc(g: ^Game) -> bool {
	if g.foe.kind != .None || rng_below(&g.rng, 100) >= ENCOUNTER_CHANCE {return false}
	total := 0
	for k in Foe_Kind {total += FOES[k].weight}
	r := rng_below(&g.rng, total)
	kind := Foe_Kind.Pirates
	for k in Foe_Kind {
		if FOES[k].weight == 0 {continue}
		if r < FOES[k].weight {
			kind = k
			break
		}
		r -= FOES[k].weight
	}
	begin_encounter(g, kind)
	return true
}

begin_encounter :: proc(g: ^Game, kind: Foe_Kind) {
	info := FOES[kind]
	hp := info.hp_min + rng_below(&g.rng, info.hp_spread)
	g.foe = {
		kind     = kind,
		state    = roll(g, .Spot) ? .Distant : .Close,
		hp       = hp,
		hp_max   = hp,
		strength = fighting_strength(g),
	}
	g.sub = .Encounter
	g.cursor = 0
}

end_encounter :: proc(g: ^Game) {
	g.foe = {}
	if g.screen == .Sea {g.sub = .None}
	g.cursor = 0
}

// Everyone's health together: the captain's and the crew's.
fighting_strength :: proc(g: ^Game) -> int {
	s := g.health
	for k in 1 ..< g.n_crew {s += g.crew[k].hp}
	return s
}

// Your round of blows: each of the crew rolls Melee (Track against a whale); a hit does 3 to 8, more with skill.
crew_attack :: proc(g: ^Game) -> int {
	skill := g.foe.kind == .Whale ? Skill.Track : Skill.Melee
	total := 0
	for k in 0 ..< max(g.n_crew, 1) {
		v := g.crew[k].skills[skill]
		if g.foe.kind == .Whale {v = max(v, g.crew[k].skills[.Melee])}
		if 1 + rng_below(&g.rng, 100) <= v {total += 3 + rng_below(&g.rng, 6) + v / 25}
	}
	g.foe.hp = max(g.foe.hp - total, 0)
	return total
}

// The foe's round. Returns hull damage and wounds dealt. May end the voyage (sunk, or the captain killed).
foe_attack :: proc(g: ^Game) -> (hull, wounds: int) {
	info := FOES[g.foe.kind]
	nb: [NAME_LEN]u8
	for _ in 0 ..< info.attacks {
		if rng_below(&g.rng, 100) >= info.chance {continue}
		if info.hull_hi > 0 {hull += info.hull_lo + rng_below(&g.rng, info.hull_hi - info.hull_lo + 1)}
		if info.wound_hi > 0 {
			w := info.wound_lo + rng_below(&g.rng, info.wound_hi - info.wound_lo + 1)
			wounds += w
			k := rng_below(&g.rng, max(g.n_crew, 1))
			if k == 0 {
				g.health = max(g.health - w, 0)
			} else {
				g.crew[k].hp -= w
				if g.crew[k].hp <= 0 {
					logf(g, "%s is killed!", member_name(g.crew[k], nb[:]))
					note(g, .Died, NO_ISLAND, int(g.crew[k].name_seed))
					remove_member(g, k)
				}
			}
		}
	}
	if hull > 0 {damage_hull(g, hull)}
	if g.screen == .Over {return}
	if g.health == 0 {end_voyage(g, .Killed)}
	return
}

// Fight a round. Returns true when the encounter is over.
fight_round :: proc(g: ^Game) -> bool {
	dealt := crew_attack(g)
	if g.foe.hp == 0 {
		win_fight(g)
		return true
	}
	hull, wounds := foe_attack(g)
	if g.screen == .Over {return true}
	logf(g, "Hit %d. Hull -%d, crew -%d.", dealt, hull, wounds)
	if g.foe.kind == .Pirates || g.foe.kind == .Merfolk {
		if fighting_strength(g) * 100 < g.foe.strength * BEATEN_PERCENT {
			beaten(g)
			return true
		}
	}
	return false
}

win_fight :: proc(g: ^Game) {
	sound(g, .Win)
	switch g.foe.kind {
	case .Pirates:
		loot := 30 + rng_below(&g.rng, 71) + g.foe.hp_max
		g.money = min(g.money + loot, MONEY_MAX)
		logf(g, "Pirates beaten! Loot: %d.", loot)
		note(g, .Victory, NO_ISLAND, int(Foe_Kind.Pirates))
	case .Monster:
		salvage := 50 + rng_below(&g.rng, 101)
		g.money = min(g.money + salvage, MONEY_MAX)
		logf(g, "Monster slain! Salvage %d.", salvage)
		note(g, .Victory, NO_ISLAND, int(Foe_Kind.Monster))
	case .Whale:
		n := stow(g, .Whale_Oil, 4 + rng_below(&g.rng, 5))
		logf(g, "Whale taken: %d oil.", n)
		note(g, .Victory, NO_ISLAND, int(Foe_Kind.Whale))
	case .Merfolk:
		n := stow(g, .Pearls, 1 + rng_below(&g.rng, 3))
		logf(g, "Merfolk flee: %d pearls.", n)
		note(g, .Victory, NO_ISLAND, int(Foe_Kind.Merfolk))
	case .None:
	}
	end_encounter(g)
}

// Beaten by pirates (or merfolk): they take half the money and half of each good, and leave.
beaten :: proc(g: ^Game) {
	sound(g, .Lose)
	taken := g.money / 2
	g.money -= taken
	if g.foe.kind == .Pirates {
		for good in Good {g.cargo[good] -= g.cargo[good] / 2}
		logf(g, "Robbed of %d and cargo!", taken)
	} else {
		logf(g, "Robbed of %d!", taken)
	}
	note(g, .Robbed, NO_ISLAND, taken)
	end_encounter(g)
}

// As many as fit in the hold, up to n. Returns how many.
stow :: proc(g: ^Game, good: Good, n: int) -> int {
	k := 0
	for k < n && hold_used(g) + GOODS[good].tons <= hold_tons(g) && g.cargo[good] < CARGO_MAX {
		g.cargo[good] += 1
		k += 1
	}
	return k
}

// Flee: a Pilot roll, easier in a faster ship. A failure gives the foe a free round. True when away.
flee :: proc(g: ^Game) -> bool {
	chance := best(g, .Pilot) + int(ship_speed(g) * 30) // a sloop with a base pilot: 35%
	if g.foe.state == .Distant || 1 + rng_below(&g.rng, 100) <= chance {
		logf(g, "You get away.")
		end_encounter(g)
		return true
	}
	hull, wounds := foe_attack(g)
	if g.screen != .Over {logf(g, "Caught! Hull -%d, crew -%d.", hull, wounds)}
	return false
}

// Parley: a Bargain roll. Pirates let you go; merfolk deal better. A bad failure with merfolk starts a fight.
parley :: proc(g: ^Game) {
	r := 1 + rng_below(&g.rng, 100)
	ok := r <= best(g, .Bargain) + 20
	switch g.foe.kind {
	case .Pirates:
		if ok {
			logf(g, "They let you pass.")
			end_encounter(g)
		} else {
			logf(g, "They laugh, and attack.")
			foe_attack(g)
		}
	case .Merfolk:
		g.foe.parleyed = true
		if ok {
			g.foe.friendly = true
			logf(g, "The merfolk warm to you.")
		} else if r > 90 {
			logf(g, "Insulted, they attack!")
			g.foe.hostile = true
			foe_attack(g)
		} else {
			logf(g, "They hear you out.")
		}
	case .None, .Monster, .Whale:
	}
}

bribe_cost :: proc(g: ^Game) -> int {return max(20, g.money / 10)}

bribe :: proc(g: ^Game) -> bool {
	c := bribe_cost(g)
	if c > g.money {return false}
	g.money -= c
	logf(g, "Paid %d to pass.", c)
	end_encounter(g)
	return true
}

// Merfolk prices: they sell their pearls and coral cheaply and buy your goods dearly; better after a good parley.
merfolk_sells :: proc(g: ^Game, good: Good) -> int {
	pct := g.foe.friendly ? 50 : 60
	return max(1, base_value(good) * pct / 100)
}

merfolk_pays :: proc(g: ^Game, good: Good) -> int {
	pct := g.foe.friendly ? 130 : 120
	return max(1, base_value(good) * pct / 100)
}

// What the merfolk would pay for every land good aboard.
merfolk_offer :: proc(g: ^Game) -> int {
	v := 0
	for good in Good {
		if !is_sea_good(good) {v += g.cargo[good] * merfolk_pays(g, good)}
	}
	return v
}

merfolk_buy :: proc(g: ^Game, good: Good) -> bool {
	p := merfolk_sells(g, good)
	if p > g.money || hold_used(g) + GOODS[good].tons > hold_tons(g) || g.cargo[good] >= CARGO_MAX {return false}
	g.money -= p
	g.cargo[good] += 1
	return true
}

merfolk_sell_all :: proc(g: ^Game) -> int {
	v := merfolk_offer(g)
	for good in Good {
		if !is_sea_good(good) {g.cargo[good] = 0}
	}
	g.money = min(g.money + v, MONEY_MAX)
	return v
}
