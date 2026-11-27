package game

import "core:fmt"

// Crew and professions (Phase 6). The C++ game used Basic Roleplaying rules (characteristics and about fifty percentile
// skills). The user chose eight percentile skills drawn from that list, a captain plus a few crew who can die or leave,
// and sailors hired in port for wages (November 27, 2026). A ship's roll uses the best skill aboard.
//
// What each skill does now:
//   Navigate  up to +20% speed (a better course)
//   Pilot     slower fouling (keeping clear of weed and shallows)
//   Repair    faster careening (10 turns down to 5); hull repairs come in Phase 7
//   Spot      see islands up to 3 leagues farther
//   Track     fishing: food at sea
//   Bargain   up to 4% off what you pay and on top of what you are paid
//   Gaming    a chance to swap a losing third card in the dark alley
//   Melee     fights, from Phase 8
// Every effect starts above the base level, so a crew of base skills plays exactly as Phases 1 to 5 did.

Skill :: enum u8 {
	Navigate,
	Pilot,
	Repair,
	Spot,
	Track,
	Bargain,
	Gaming,
	Melee,
}

SKILL_NAMES := [Skill]string {
	.Navigate = "Navigate",
	.Pilot    = "Pilot",
	.Repair   = "Repair",
	.Spot     = "Spot",
	.Track    = "Track",
	.Bargain  = "Bargain",
	.Gaming   = "Gaming",
	.Melee    = "Melee",
}

// Everyone's starting level, from the C++ game's base chances where it had them.
BASE_SKILL := [Skill]int {
	.Navigate = 10,
	.Pilot    = 5,
	.Repair   = 15,
	.Spot     = 25,
	.Track    = 10,
	.Bargain  = 5,
	.Gaming   = 10,
	.Melee    = 25,
}

Profession :: enum u8 {
	Hunter,
	Sailor,
	Thief,
	Warrior,
	Custom,
}

PROFESSION_NAMES := [Profession]string {
	.Hunter  = "Hunter",
	.Sailor  = "Sailor",
	.Thief   = "Thief",
	.Warrior = "Warrior",
	.Custom  = "Captain",
}

// What a profession adds to the base: 120 points each, as a custom captain gets to spend.
PACKAGE := [Profession][Skill]int {
	.Hunter  = #partial [Skill]int{.Track = 40, .Spot = 40, .Navigate = 20, .Melee = 20},
	.Sailor  = #partial [Skill]int{.Pilot = 40, .Navigate = 40, .Repair = 20, .Spot = 20},
	.Thief   = #partial [Skill]int{.Bargain = 40, .Gaming = 40, .Spot = 20, .Melee = 20},
	.Warrior = #partial [Skill]int{.Melee = 40, .Pilot = 20, .Repair = 20, .Spot = 20, .Track = 20},
	.Custom  = {},
}

SKILL_POINTS :: 120 // a custom captain's points
SKILL_STEP :: 10
SKILL_CAP :: 90 // no skill is raised past this at the start
CREW_MAX :: 7 // the captain and six
START_CREW :: 3
CANDIDATES_MAX :: 3
TAVERN_CHANCE :: 50
WAGE_PERIOD :: 10 // wages are counted per ten turns
WAGE_MAX :: 20
FISH_TURNS :: 5
QUICK :: -1 // Begin's arg for a quick start
NAME_LEN :: 8

Member :: struct {
	name_seed:  u32, // the name is rebuilt from this
	profession: Profession,
	skills:     [Skill]int, // 0 ..= 100
	hp:         int, // the captain's is g.health
	wage:       int, // per WAGE_PERIOD turns; the captain draws none
}

// A name in a sailor's style, built from the member's name seed.
member_name :: proc(m: Member, buf: []u8) -> string {
	CONSONANTS := "bdgklmnprstv"
	VOWELS := "aeiou"
	r := rng_make(u64(m.name_seed))
	n := min(3 + rng_below(&r, 3) + rng_below(&r, 3), len(buf), NAME_LEN)
	vowel_first := rng_below(&r, 3) == 0
	for i in 0 ..< n {
		vowel := (i % 2 == 0) == vowel_first
		buf[i] = vowel ? VOWELS[rng_below(&r, 5)] : CONSONANTS[rng_below(&r, 12)]
	}
	buf[0] -= 'a' - 'A'
	return string(buf[:n])
}

new_name_seed :: proc(r: ^Rng) -> u32 {
	return u32(rng_next(r)) | 1
}

profession_skills :: proc(p: Profession) -> (s: [Skill]int) {
	for k in Skill {s[k] = BASE_SKILL[k] + PACKAGE[p][k]}
	return
}

// A sailor for hire: half a profession's package, a knack for one skill, and a wage that follows the skill.
hireling :: proc(r: ^Rng) -> (m: Member) {
	m.name_seed = new_name_seed(r)
	m.profession = Profession(rng_below(r, 4))
	extra := 0
	for k in Skill {
		m.skills[k] = BASE_SKILL[k] + PACKAGE[m.profession][k] / 2
		extra += PACKAGE[m.profession][k] / 2
	}
	knack := Skill(rng_below(r, len(Skill)))
	bump := 5 * (1 + rng_below(r, 4))
	m.skills[knack] = min(m.skills[knack] + bump, SKILL_CAP)
	extra += bump
	m.hp = STAT_MAX
	m.wage = clamp(1 + extra / 25, 1, WAGE_MAX)
	return
}

// The captain a world starts with before a voyage begins, and the one an older save is given: base skills only.
plain_captain :: proc(g: ^Game) {
	g.crew[0] = {
		name_seed  = u32(g.seed ~ (g.seed >> 32)) | 1,
		profession = .Custom,
		skills     = BASE_SKILL,
		hp         = STAT_MAX,
	}
	g.n_crew = 1
}

// Starts a voyage on a fresh world with a captain of the given profession and skills, and (normally) a starting crew.
begin_voyage :: proc(g: ^Game, p: Profession, skills: [Skill]int, with_crew := true) {
	start_world(g, g.next_seed)
	g.next_seed = rng_next(&g.rng)
	r := rng_make(g.seed ~ 0xC4_E3_00_57)
	g.crew[0] = {
		name_seed  = new_name_seed(&r),
		profession = p,
		skills     = skills,
		hp         = STAT_MAX,
	}
	g.n_crew = 1
	if with_crew {
		for _ in 0 ..< START_CREW {
			g.crew[g.n_crew] = hireling(&r)
			g.n_crew += 1
		}
	}
	g.turn = 0
	g.screen = g.docked == NO_ISLAND ? .Sea : .Docked
	g.sub = .None
	g.has_voyage = true
	g.new_best = false
	g.cursor = 0
	if g.docked != NO_ISLAND {
		logf(g, "Home port: %s.", island_name(g, g.docked))
		make_candidates(g)
	} else {
		logf(g, "A new voyage begins.")
	}
	note(g, .Began, g.docked, 0)
	g.want_save = true
}

// The best level of a skill aboard.
best :: proc(g: ^Game, s: Skill) -> int {
	v := 0
	for k in 0 ..< max(g.n_crew, 1) {v = max(v, g.crew[k].skills[s])}
	return clamp(v, 0, 100)
}

// d100 against the best skill aboard.
roll :: proc(g: ^Game, s: Skill) -> bool {
	return 1 + rng_below(&g.rng, 100) <= best(g, s)
}

speed_factor :: proc(g: ^Game) -> f32 {
	return 1 + f32(max(0, best(g, .Navigate) - 20)) / 400
}

foul_per_turn :: proc(g: ^Game) -> int {
	f := (FOUL_PER_TURN * (200 - best(g, .Pilot)) + 100) / 200
	return g.fitted[.Copper] > 0 ? (f + 1) / 2 : f // copper sheathing halves it
}

view_distance :: proc(g: ^Game) -> f32 {
	return VIEW_DISTANCE + f32(max(0, best(g, .Spot) - 25) / 25)
}

careen_turns :: proc(g: ^Game) -> int {
	return CAREEN_TURNS - max(0, best(g, .Repair) - 15) / 17
}

bargain_percent :: proc(g: ^Game) -> int {
	return max(0, best(g, .Bargain) - 5) / 20
}

gaming_chance :: proc(g: ^Game) -> int {
	return max(0, best(g, .Gaming) - 10) / 3
}

// What you pay for one of the good, and what you are paid, after bargaining.
your_cost :: proc(g: ^Game, i: int, good: Good) -> int {
	return max(1, sell_price(g, i, good) * (100 - bargain_percent(g)) / 100)
}

your_take :: proc(g: ^Game, i: int, good: Good) -> int {
	return max(1, buy_price(g, i, good) * (100 + bargain_percent(g)) / 100)
}

wages :: proc(g: ^Game) -> int {
	w := 0
	for k in 1 ..< g.n_crew {w += g.crew[k].wage}
	return w
}

remove_member :: proc(g: ^Game, k: int) {
	for j in k ..< g.n_crew - 1 {g.crew[j] = g.crew[j + 1]}
	g.n_crew -= 1
}

// Starvation hurts everyone; a crew member who reaches 0 dies. The captain's health is handled in tick.
crew_starve :: proc(g: ^Game) {
	k := 1
	for k < g.n_crew {
		g.crew[k].hp -= 1
		if g.crew[k].hp > 0 {
			k += 1
			continue
		}
		buf: [NAME_LEN]u8
		logf(g, "%s has died.", member_name(g.crew[k], buf[:]))
		note(g, .Died, g.docked, int(g.crew[k].name_seed))
		remove_member(g, k)
	}
}

crew_recover :: proc(g: ^Game) {
	for k in 1 ..< g.n_crew {g.crew[k].hp = min(g.crew[k].hp + 1, STAT_MAX)}
}

// On docking: wages owed since the last port are paid in turn, and anyone who cannot be paid leaves. Hungry crew may
// leave too. Returns what was paid.
settle_crew :: proc(g: ^Game) -> int {
	paid := 0
	k := 1
	buf: [NAME_LEN]u8
	for k < g.n_crew {
		owed := (g.crew[k].wage * g.wage_turns + WAGE_PERIOD / 2) / WAGE_PERIOD
		if owed <= g.money {
			g.money -= owed
			paid += owed
			k += 1
			continue
		}
		logf(g, "%s left, unpaid.", member_name(g.crew[k], buf[:]))
		note(g, .Deserted, g.docked, int(g.crew[k].name_seed))
		remove_member(g, k)
	}
	g.wage_turns = 0
	if g.satiety < STAT_MAX / 4 {
		k = 1
		for k < g.n_crew {
			if rng_below(&g.rng, 2) == 0 {
				k += 1
				continue
			}
			logf(g, "%s left, hungry.", member_name(g.crew[k], buf[:]))
			note(g, .Deserted, g.docked, int(g.crew[k].name_seed))
			remove_member(g, k)
		}
	}
	return paid
}

// The sailors looking for a berth at the docked island's tavern (none without one). Called on docking.
make_candidates :: proc(g: ^Game) {
	g.n_candidates = 0
	i := g.docked
	if i == NO_ISLAND || .Tavern not_in g.districts[i] {return}
	for g.n_candidates < CANDIDATES_MAX {
		g.candidates[g.n_candidates] = hireling(&g.rng)
		g.n_candidates += 1
	}
}

hire :: proc(g: ^Game, k: int) -> bool {
	if k < 0 || k >= g.n_candidates || g.n_crew >= CREW_MAX {return false}
	g.crew[g.n_crew] = g.candidates[k]
	g.n_crew += 1
	note(g, .Hired, g.docked, int(g.candidates[k].name_seed))
	for j in k ..< g.n_candidates - 1 {g.candidates[j] = g.candidates[j + 1]}
	g.n_candidates -= 1
	return true
}

dismiss :: proc(g: ^Game, k: int) -> bool {
	if k < 1 || k >= g.n_crew || g.docked == NO_ISLAND {return false}
	note(g, .Dismissed, g.docked, int(g.crew[k].name_seed))
	remove_member(g, k)
	return true
}

// Fish for FISH_TURNS turns, the ship hove to. Each turn a Track roll lands 2 to 8 rations. Returns the catch.
fish :: proc(g: ^Game) -> int {
	caught := 0
	for _ in 0 ..< FISH_TURNS {
		if roll(g, .Track) {
			n := 2 + rng_below(&g.rng, 7)
			g.rations = min(g.rations + n, RATIONS_MAX)
			caught += n
		}
		if !tick(g, false) {break}
	}
	return caught
}

// The captain's log (feature, November 27, 2026): the voyage's notable events, shown on the retirement screen and
// from the chart. When it is full the oldest entry after the first is dropped.
LOGBOOK_MAX :: 64
LOGBOOK_PAGE :: 14

Log_Kind :: enum u8 {
	Began,
	Landfall,
	Delivered,
	Hired,
	Died,
	Deserted,
	Dismissed,
	Won,
	Sold,
	New_Ship, // value: Ship_Type
	Passage, // value: fares paid
}

Log_Entry :: struct {
	turn:   int,
	kind:   Log_Kind,
	island: int, // NO_ISLAND when at sea
	value:  int, // money, or a member's name seed
}

BIG_WIN :: 100 // alley wins this large are logged
BIG_SALE :: 500 // and sales this large

note :: proc(g: ^Game, kind: Log_Kind, island: int, value: int) {
	if g.n_logbook == LOGBOOK_MAX {
		for j in 1 ..< LOGBOOK_MAX - 1 {g.logbook[j] = g.logbook[j + 1]}
		g.n_logbook -= 1
	}
	g.logbook[g.n_logbook] = {g.turn, kind, island, value}
	g.n_logbook += 1
}

logbook_text :: proc(g: ^Game, e: Log_Entry, buf: []u8) -> string {
	at := e.island == NO_ISLAND ? "sea" : island_name(g, e.island)
	nb: [NAME_LEN]u8
	who := member_name(Member{name_seed = u32(e.value)}, nb[:])
	switch e.kind {
	case .Began:
		return fmt.bprintf(buf, "%d: Sailed from %s.", e.turn, at)
	case .Landfall:
		return fmt.bprintf(buf, "%d: First landfall, %s.", e.turn, at)
	case .Delivered:
		return fmt.bprintf(buf, "%d: Delivered at %s: %d.", e.turn, at, e.value)
	case .Hired:
		return fmt.bprintf(buf, "%d: Hired %s at %s.", e.turn, who, at)
	case .Died:
		return fmt.bprintf(buf, "%d: %s died at %s.", e.turn, who, at)
	case .Deserted:
		return fmt.bprintf(buf, "%d: %s left at %s.", e.turn, who, at)
	case .Dismissed:
		return fmt.bprintf(buf, "%d: Paid off %s at %s.", e.turn, who, at)
	case .Won:
		return fmt.bprintf(buf, "%d: Won %d at %s's alley.", e.turn, e.value, at)
	case .Sold:
		return fmt.bprintf(buf, "%d: A sale of %d at %s.", e.turn, e.value, at)
	case .New_Ship:
		name := e.value >= 0 && e.value <= int(max(Ship_Type)) ? SHIPS[Ship_Type(e.value)].name : "ship"
		return fmt.bprintf(buf, "%d: Bought a %s at %s.", e.turn, name, at)
	case .Passage:
		return fmt.bprintf(buf, "%d: Fares at %s: %d.", e.turn, at, e.value)
	}
	return ""
}

logbook_pages :: proc(g: ^Game) -> int {
	return max(1, (g.n_logbook + LOGBOOK_PAGE - 1) / LOGBOOK_PAGE)
}
