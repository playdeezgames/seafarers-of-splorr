package game

import "core:math"

// Wind, calendar, storms and rats (Phase 9). The user chose storms drawn on the map, a moderate wind (from 60% of
// speed into the wind to 130% running before it), seasons that shift the wind, the storms and some prices, and rats
// that come aboard in port, breed, and eat rations and cargo until hunted (November 28, 2026).
//
// The weather has its own generator (g.weather), saved with the voyage, so it never disturbs the rolls that decide
// fights, offers and markets.

// The calendar: a turn is a day, a month is thirty days, and a voyage starts on the first of March.
MONTH_TURNS :: 30
START_MONTH :: 2 // March

MONTH_NAMES := [12]string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

Season :: enum u8 {
	Spring,
	Summer,
	Autumn,
	Winter,
}

SEASON_NAMES := [Season]string {
	.Spring = "Spring",
	.Summer = "Summer",
	.Autumn = "Autumn",
	.Winter = "Winter",
}

month :: proc(turn: int) -> int {return (START_MONTH + turn / MONTH_TURNS) % 12}
day_of_month :: proc(turn: int) -> int {return turn % MONTH_TURNS + 1}
year :: proc(turn: int) -> int {return (START_MONTH + turn / MONTH_TURNS) / 12 + 1}

season :: proc(turn: int) -> Season {
	switch month(turn) {
	case 2, 3, 4: return .Spring
	case 5, 6, 7: return .Summer
	case 8, 9, 10: return .Autumn
	}
	return .Winter
}

// Prices by season, in percent of a commodity's price: grain is cheap after the harvest and dear in winter, wool cheap
// after the shearing, fish and timber dearer when the weather keeps boats and woodcutters home.
SEASON_PRICE := [Season][Commodity]int {
	.Spring = {.Grain = 110, .Fish = 100, .Timber = 100, .Wool = 85, .Ore = 100, .Spice = 100},
	.Summer = {.Grain = 100, .Fish = 90, .Timber = 95, .Wool = 100, .Ore = 100, .Spice = 100},
	.Autumn = {.Grain = 80, .Fish = 100, .Timber = 100, .Wool = 100, .Ore = 100, .Spice = 110},
	.Winter = {.Grain = 125, .Fish = 115, .Timber = 110, .Wool = 120, .Ore = 100, .Spice = 100},
}

// The wind: the direction it blows from, in degrees, and its force.
Wind_Force :: enum u8 {
	Calm,
	Light,
	Fresh,
	Strong,
}

WIND_NAMES := [Wind_Force]string {
	.Calm   = "calm",
	.Light  = "light",
	.Fresh  = "fresh",
	.Strong = "strong",
}

// Speed with the wind dead astern is centre + swing; dead ahead, centre - swing. Strong gives the user's 60% to 130%.
WIND_CENTRE := [Wind_Force]f32 {
	.Calm   = 0.70,
	.Light  = 0.90,
	.Fresh  = 0.95,
	.Strong = 0.95,
}
WIND_SWING := [Wind_Force]f32 {
	.Calm   = 0,
	.Light  = 0.15,
	.Fresh  = 0.25,
	.Strong = 0.35,
}

// Each turn, the percent chance the wind veers or backs, and the per mille chance its force changes, by season. When
// the force changes it rises with WIND_RISE percent, else falls.
WIND_SHIFT := [Season]int {
	.Spring = 6,
	.Summer = 4,
	.Autumn = 10,
	.Winter = 12,
}
FORCE_CHANGE :: 40
WIND_RISE := [Season]int {
	.Spring = 50,
	.Summer = 35,
	.Autumn = 60,
	.Winter = 65,
}

// Storms: per mille a turn by season, doubled in a strong wind. One lasts 60 to 150 turns, drifts downwind, and
// batters any ship inside it.
STORM_CHANCE := [Season]int {
	.Spring = 4,
	.Summer = 2,
	.Autumn = 10,
	.Winter = 12,
}
STORMS_MAX :: 6
STORM_NEAR :: 12 // storms form this far from the ship or farther
STORM_FAR :: 30 // and no farther than this
STORM_DAMAGE_LO :: 2
STORM_DAMAGE_HI :: 6
STORM_PUSH :: 0.3 // tiles a turn the wind drives a ship inside a storm

Storm :: struct {
	x, y:   f32, // the centre, in tiles
	radius: f32, // tiles, 1.5 ..= 4
	turns:  int, // left to live
	seen:   bool, // the ship has had it in view
}

// Rats: a chance to come aboard each time you dock; aboard they breed, eat rations and spoil cargo.
RAT_CHANCE :: 25 // percent, on docking
RATS_MAX :: 250
RAT_BREED :: 8 // percent a turn that the rats aboard grow by a fifth (at least one)
RAT_APPETITE :: 20 // rats to eat one ration a turn
HUNT_TURNS :: 2

// Rats gnaw these.
RAT_FOOD :: bit_set[Good]{.Flour, .Salt_Fish, .Rope, .Sailcloth, .Woolens}

// The weather at the start of a voyage.
start_weather :: proc(g: ^Game) {
	g.weather = rng_make(g.seed ~ 0x3E_A7_4E_12)
	g.wind_dir = 45 * rng_below(&g.weather, 8)
	g.wind_force = .Fresh
	g.n_storms = 0
	g.rats = 0
}

// The wind's effect on the speed for the ship's heading: 1 is none.
wind_factor :: proc(g: ^Game) -> f32 {
	if g.weather_off {return 1}
	downwind := f32(g.wind_dir + 180) * math.PI / 180
	a := f32(g.ship.heading) * math.PI / 180 - downwind
	return WIND_CENTRE[g.wind_force] + WIND_SWING[g.wind_force] * math.cos(a)
}

// A turn of weather: the wind shifts, storms drift, form and blow out, the rats breed and feed. Called from tick.
weather_turn :: proc(g: ^Game) {
	if g.weather_off {return}
	s := season(g.turn)
	r := &g.weather
	if rng_below(r, 100) < WIND_SHIFT[s] {
		step := 15 * (1 + rng_below(r, 3))
		g.wind_dir = wrap_heading(g.wind_dir + (rng_below(r, 2) == 0 ? step : -step))
	}
	if rng_below(r, 1000) < FORCE_CHANGE {
		f := int(g.wind_force) + (rng_below(r, 100) < WIND_RISE[s] ? 1 : -1)
		g.wind_force = Wind_Force(clamp(f, 0, int(max(Wind_Force))))
	}

	// Storms drift downwind, a little faster in a stronger wind.
	rad := f32(g.wind_dir + 180) * math.PI / 180
	drift := 0.15 + 0.1 * f32(g.wind_force)
	k := 0
	for k < g.n_storms {
		st := &g.storms[k]
		st.x += math.sin(rad) * drift
		st.y -= math.cos(rad) * drift
		st.turns -= 1
		if st.turns <= 0 || !in_world(st.x) || !in_world(st.y) {
			g.storms[k] = g.storms[g.n_storms - 1]
			g.n_storms -= 1
			continue
		}
		k += 1
	}
	chance := STORM_CHANCE[s] * (g.wind_force == .Strong ? 2 : 1)
	if g.n_storms < STORMS_MAX && rng_below(r, 1000) < chance {spawn_storm(g)}

	feed_rats(g)
}

spawn_storm :: proc(g: ^Game) {
	r := &g.weather
	a := f32(rng_below(r, 360)) * math.PI / 180
	d := f32(STORM_NEAR + rng_below(r, STORM_FAR - STORM_NEAR + 1))
	g.storms[g.n_storms] = {
		x      = clamp(g.ship.x + math.sin(a) * d, 2, WORLD_SIZE - 2),
		y      = clamp(g.ship.y - math.cos(a) * d, 2, WORLD_SIZE - 2),
		radius = 1.5 + f32(rng_below(r, 26)) / 10,
		turns  = 60 + rng_below(r, 91),
	}
	g.n_storms += 1
}

// The storm the point is inside, or -1.
storm_at :: proc(g: ^Game, x, y: f32) -> int {
	for k in 0 ..< g.n_storms {
		st := g.storms[k]
		dx, dy := x - st.x, y - st.y
		if dx * dx + dy * dy <= st.radius * st.radius {return k}
	}
	return -1
}

in_storm :: proc(g: ^Game) -> bool {return g.docked == NO_ISLAND && storm_at(g, g.ship.x, g.ship.y) >= 0}

// True when any of the storm is within the ship's view.
storm_in_view :: proc(g: ^Game, k: int) -> bool {
	st := g.storms[k]
	dx, dy := st.x - g.ship.x, st.y - g.ship.y
	reach := view_distance(g) + st.radius
	return dx * dx + dy * dy <= reach * reach
}

// Marks storms newly in view. Returns the last one newly seen, or -1.
look_storms :: proc(g: ^Game) -> int {
	sighted := -1
	for k in 0 ..< g.n_storms {
		if !g.storms[k].seen && storm_in_view(g, k) {
			g.storms[k].seen = true
			sighted = k
		}
	}
	return sighted
}

// The compass point from the ship to a storm's centre.
storm_bearing :: proc(g: ^Game, k: int) -> int {
	dx, dy := g.storms[k].x - g.ship.x, g.storms[k].y - g.ship.y
	return wrap_heading(int(math.round(math.atan2(dx, -dy) * 180 / math.PI)))
}

// A turn inside a storm: the hull takes a battering (halved by a Pilot roll, worse in a strong wind) and the wind
// drives the ship downwind. Returns the damage. May sink the ship.
storm_hit :: proc(g: ^Game) -> int {
	dmg := STORM_DAMAGE_LO + rng_below(&g.weather, STORM_DAMAGE_HI - STORM_DAMAGE_LO + 1)
	if g.wind_force == .Strong {dmg += 2}
	if roll(g, .Pilot) {dmg = (dmg + 1) / 2}
	rad := f32(g.wind_dir + 180) * math.PI / 180
	nx, ny := g.ship.x + math.sin(rad) * STORM_PUSH, g.ship.y - math.cos(rad) * STORM_PUSH
	if in_world(nx) && in_world(ny) && !is_land(g, int(nx), int(ny)) {g.ship.x, g.ship.y = nx, ny}
	damage_hull(g, dmg)
	return dmg
}

// Rats aboard breed, eat rations and spoil cargo, a turn's worth.
feed_rats :: proc(g: ^Game) {
	if g.rats == 0 {return}
	r := &g.weather
	if rng_below(r, 100) < RAT_BREED {g.rats = min(g.rats + max(1, g.rats / 5), RATS_MAX)}
	eat := g.rats / RAT_APPETITE + (rng_below(r, RAT_APPETITE) < g.rats % RAT_APPETITE ? 1 : 0)
	g.rations = max(g.rations - eat, 0)
	if rng_below(r, 1000) < g.rats * 2 {
		n := 0
		for good in RAT_FOOD {if g.cargo[good] > 0 {n += 1}}
		if n > 0 {
			pick := rng_below(r, n)
			for good in RAT_FOOD {
				if g.cargo[good] == 0 {continue}
				if pick == 0 {
					g.cargo[good] -= 1
					g.spoiled += 1
					break
				}
				pick -= 1
			}
		}
	}
}

// On docking: perhaps rats come aboard. Returns how many.
rats_board :: proc(g: ^Game) -> int {
	if g.weather_off || rng_below(&g.weather, 100) >= RAT_CHANCE {return 0}
	n := 2 + rng_below(&g.weather, 5)
	g.rats = min(g.rats + n, RATS_MAX)
	return n
}

// Hunt rats: HUNT_TURNS turns, and each aboard who makes a Track roll kills a few. Returns how many were killed.
hunt_rats :: proc(g: ^Game) -> int {
	killed := 0
	for _ in 0 ..< HUNT_TURNS {
		for k in 0 ..< max(g.n_crew, 1) {
			v := g.crew[k].skills[.Track]
			if 1 + rng_below(&g.rng, 100) <= v {killed += 3 + rng_below(&g.rng, 6) + v / 20}
		}
		if !tick(g, false) {break}
	}
	killed = min(killed, g.rats)
	g.rats -= killed
	return killed
}
