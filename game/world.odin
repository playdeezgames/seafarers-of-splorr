package game

import "core:math"

WORLD_SIZE :: 120 // the world is WORLD_SIZE by WORLD_SIZE tiles
ISLAND_MAX :: 40
ISLAND_GAP :: 15 // minimum distance between island seeds (Classic kept a minimum gap too)
ISLAND_REACH :: 2 // an island's blocks wander at most this far from its seed block
VIEW_DISTANCE :: 9 // islands with land this close are charted
DOCK_RANGE :: 1.5 // docking needs land of the island this close
NAME_MAX :: 9
NO_ISLAND :: -1

Island :: struct {
	x, y:     int, // top-left tile of the seed block; the island lies within x-2 ..= x+3 and y-2 ..= y+3
	name:     [NAME_MAX]u8,
	name_len: int,
	charted:  bool,
}

// Builds islands and the land grid from g.seed. Uses its own generator so the world depends only on the seed: a save
// stores the seed and the charted flags, not the map.
generate_world :: proc(g: ^Game) {
	r := rng_make(g.seed ~ 0x15_1A_4D_5E_ED)
	g.n_islands = 0
	g.land = {}
	lo, hi := ISLAND_REACH + 2, WORLD_SIZE - ISLAND_REACH - 4
	for _ in 0 ..< 4000 {
		if g.n_islands == ISLAND_MAX {break}
		x := lo + rng_below(&r, hi - lo)
		y := lo + rng_below(&r, hi - lo)
		ok := true
		for i in 0 ..< g.n_islands {
			dx, dy := g.islands[i].x - x, g.islands[i].y - y
			if dx * dx + dy * dy < ISLAND_GAP * ISLAND_GAP {
				ok = false
				break
			}
		}
		if !ok {continue}
		idx := g.n_islands
		g.islands[idx] = {x = x, y = y}
		grow_island(g, &r, idx)
		name_island(g, &r, idx)
		g.n_islands += 1
	}
}

// An island is a union of 2 by 2 blocks along a short random walk. Every land tile then has a land neighbour across and
// one up or down, which is exactly the set of shapes the coastline tiles cover.
grow_island :: proc(g: ^Game, r: ^Rng, idx: int) {
	is := &g.islands[idx]
	bx, by := is.x, is.y
	steps := 1 + rng_below(r, 7)
	for _ in 0 ..< steps {
		for dy in 0 ..< 2 {
			for dx in 0 ..< 2 {
				g.land[(by + dy) * WORLD_SIZE + bx + dx] = u8(idx + 1)
			}
		}
		bx = clamp(bx + rng_below(r, 3) - 1, is.x - ISLAND_REACH, is.x + ISLAND_REACH)
		by = clamp(by + rng_below(r, 3) - 1, is.y - ISLAND_REACH, is.y + ISLAND_REACH)
	}
}

// Classic's names: consonants and vowels alternate (starting with either), length 3 to 9 weighted towards 6.
name_island :: proc(g: ^Game, r: ^Rng, idx: int) {
	CONSONANTS := "hklmp"
	VOWELS := "aeiou"
	WEIGHTS := [7]int{1, 3, 6, 7, 6, 3, 1} // lengths 3 ..= 9
	is := &g.islands[idx]
	for _ in 0 ..< 20 {
		roll := rng_below(r, 27)
		n := 3
		for w in WEIGHTS {
			if roll < w {break}
			roll -= w
			n += 1
		}
		vowel_first := rng_below(r, 2) == 0
		for i in 0 ..< n {
			vowel := (i % 2 == 0) == vowel_first
			is.name[i] = vowel ? VOWELS[rng_below(r, 5)] : CONSONANTS[rng_below(r, 5)]
		}
		is.name[0] -= 'a' - 'A'
		is.name_len = n
		unique := true
		for j in 0 ..< idx {
			if island_name(g, j) == island_name(g, idx) {
				unique = false
				break
			}
		}
		if unique {return}
	}
}

island_name :: proc(g: ^Game, i: int) -> string {
	return string(g.islands[i].name[:g.islands[i].name_len])
}

// The island index at a tile, or NO_ISLAND for water and anything off the map.
land_at :: proc(g: ^Game, tx, ty: int) -> int {
	if tx < 0 || ty < 0 || tx >= WORLD_SIZE || ty >= WORLD_SIZE {return NO_ISLAND}
	return int(g.land[ty * WORLD_SIZE + tx]) - 1
}

is_land :: proc(g: ^Game, tx, ty: int) -> bool {
	return land_at(g, tx, ty) != NO_ISLAND
}

// Which neighbours of a land tile belong to the same island: 1 north, 2 east, 4 south, 8 west. The web layer picks the
// coastline tile from it.
land_mask :: proc(g: ^Game, tx, ty: int) -> int {
	i := land_at(g, tx, ty)
	if i == NO_ISLAND {return 0}
	m := 0
	if land_at(g, tx, ty - 1) == i {m |= 1}
	if land_at(g, tx + 1, ty) == i {m |= 2}
	if land_at(g, tx, ty + 1) == i {m |= 4}
	if land_at(g, tx - 1, ty) == i {m |= 8}
	return m
}

// Distance from a point (in tiles) to the centre of the island's nearest land tile.
island_distance :: proc(g: ^Game, i: int, x, y: f32) -> f32 {
	is := &g.islands[i]
	best := f32(1e9)
	for ty in is.y - ISLAND_REACH ..= is.y + ISLAND_REACH + 1 {
		for tx in is.x - ISLAND_REACH ..= is.x + ISLAND_REACH + 1 {
			if land_at(g, tx, ty) != i {continue}
			dx, dy := f32(tx) + 0.5 - x, f32(ty) + 0.5 - y
			best = min(best, dx * dx + dy * dy)
		}
	}
	return math.sqrt(best)
}

// Compass bearing in whole degrees from the ship to the island's nearest land.
bearing_to :: proc(g: ^Game, i: int) -> int {
	is := &g.islands[i]
	best := f32(1e9)
	bx, by: f32
	for ty in is.y - ISLAND_REACH ..= is.y + ISLAND_REACH + 1 {
		for tx in is.x - ISLAND_REACH ..= is.x + ISLAND_REACH + 1 {
			if land_at(g, tx, ty) != i {continue}
			dx, dy := f32(tx) + 0.5 - g.ship.x, f32(ty) + 0.5 - g.ship.y
			if d := dx * dx + dy * dy; d < best {
				best, bx, by = d, dx, dy
			}
		}
	}
	deg := math.atan2(bx, -by) * 180 / math.PI
	return wrap_heading(int(math.round(deg)))
}

// Charts every island with land in view. Returns the last island newly charted, or NO_ISLAND.
look :: proc(g: ^Game) -> int {
	sighted := NO_ISLAND
	for i in 0 ..< g.n_islands {
		if g.islands[i].charted {continue}
		if island_distance(g, i, g.ship.x, g.ship.y) <= VIEW_DISTANCE {
			g.islands[i].charted = true
			sighted = i
		}
	}
	return sighted
}

// Charted islands sorted nearest first, at most len(out). Returns how many were written.
charted_by_distance :: proc(g: ^Game, out: []int) -> int {
	all: [ISLAND_MAX]int
	dist: [ISLAND_MAX]f32
	n := 0
	for i in 0 ..< g.n_islands {
		if !g.islands[i].charted {continue}
		d := island_distance(g, i, g.ship.x, g.ship.y)
		pos := n
		for pos > 0 && dist[pos - 1] > d {
			all[pos], dist[pos] = all[pos - 1], dist[pos - 1]
			pos -= 1
		}
		all[pos], dist[pos] = i, d
		n += 1
	}
	n = min(n, len(out))
	copy(out, all[:n])
	return n
}

// Islands close enough to dock at, nearest first. (Classic docked at the farthest one in range; this fixes that.)
dockable :: proc(g: ^Game, out: []int) -> int {
	near: [ISLAND_MAX]int
	n := charted_by_distance(g, near[:])
	k := 0
	for j in 0 ..< n {
		if k == len(out) {break}
		if island_distance(g, near[j], g.ship.x, g.ship.y) <= DOCK_RANGE {
			out[k] = near[j]
			k += 1
		}
	}
	return k
}

// A water tile next to the island to moor at, as a position in tiles (a tile centre).
mooring :: proc(g: ^Game, i: int) -> (x, y: f32, ok: bool) {
	is := &g.islands[i]
	for ty in is.y - ISLAND_REACH - 1 ..= is.y + ISLAND_REACH + 2 {
		for tx in is.x - ISLAND_REACH - 1 ..= is.x + ISLAND_REACH + 2 {
			if tx < 0 || ty < 0 || tx >= WORLD_SIZE || ty >= WORLD_SIZE || is_land(g, tx, ty) {continue}
			cx, cy := f32(tx) + 0.5, f32(ty) + 0.5
			if island_distance(g, i, cx, cy) <= 1.01 {return cx, cy, true}
		}
	}
	return 0, 0, false
}
