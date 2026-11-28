package game

import "core:math"

// Piloting (the user's request, November 27, 2026: islands in the way of a delivery made you steer round them by hand,
// which was less fun). Head for now sets a course: each turn under sail the ship finds a way over the sea tiles to the
// island, steers for the farthest point of that way it can see in a straight line, and stops alongside, ready to dock.
// New sightings no longer stop a ship on a course. Setting the heading or the speed yourself drops the course.

COURSE_LOOKAHEAD :: 40 // path tiles considered when picking the straight run to steer for

// The heading to steer now, and how far the straight run is, for a course to island i. ok is false when no way exists.
steer :: proc(g: ^Game, i: int) -> (heading: int, run: f32, ok: bool) {
	@(static) parent: [WORLD_SIZE * WORLD_SIZE]i32
	@(static) queue: [WORLD_SIZE * WORLD_SIZE]i32
	NONE :: -1
	sx, sy := int(g.ship.x), int(g.ship.y)
	if sx < 0 || sy < 0 || sx >= WORLD_SIZE || sy >= WORLD_SIZE {return}
	start := i32(sy * WORLD_SIZE + sx)
	goal := i32(NONE)
	DIRS := [8][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {1, -1}, {1, 1}, {-1, 1}, {-1, -1}}
	// First round the storms in view (Phase 9); if they close every way, straight through them.
	avoid := false
	for k in 0 ..< g.n_storms {if g.storms[k].seen && storm_in_view(g, k) {avoid = true}}
	for pass in 0 ..< 2 {
		if pass == 1 {
			if !avoid {break}
			avoid = false
		}
		for k in 0 ..< len(parent) {parent[k] = NONE}
		parent[start] = start
		head, tail := 0, 0
		queue[tail] = start
		tail += 1
		for head < tail {
			cur := queue[head]
			head += 1
			cx, cy := int(cur) % WORLD_SIZE, int(cur) / WORLD_SIZE
			if island_distance(g, i, f32(cx) + 0.5, f32(cy) + 0.5) <= 1.01 {
				goal = cur
				break
			}
			for d in DIRS {
				nx, ny := cx + d.x, cy + d.y
				if nx < 0 || ny < 0 || nx >= WORLD_SIZE || ny >= WORLD_SIZE || is_land(g, nx, ny) {continue}
				if d.x != 0 && d.y != 0 && (is_land(g, cx + d.x, cy) || is_land(g, cx, cy + d.y)) {continue} // no cutting corners
				if avoid && stormy(g, f32(nx) + 0.5, f32(ny) + 0.5) {continue}
				n := i32(ny * WORLD_SIZE + nx)
				if parent[n] != NONE {continue}
				parent[n] = cur
				queue[tail] = n
				tail += 1
			}
		}
		if goal != NONE {break}
	}
	if goal == NONE {return}

	// Walk back from the goal to the ship, keeping the tiles nearest the ship.
	path: [COURSE_LOOKAHEAD]i32
	n := 0
	for at := goal; at != start; at = parent[at] {
		if n < COURSE_LOOKAHEAD {
			path[n] = at
			n += 1
		} else {
			copy(path[:COURSE_LOOKAHEAD - 1], path[1:])
			path[COURSE_LOOKAHEAD - 1] = at
		}
	}
	// path now runs from the far end back towards the ship; steer for the farthest tile in clear sight.
	tx, ty := g.ship.x, g.ship.y
	if n == 0 {
		// Already on the goal tile: aim at its centre.
		tx, ty = f32(sx) + 0.5, f32(sy) + 0.5
	} else {
		for k in 0 ..< n {
			px, py := f32(int(path[k]) % WORLD_SIZE) + 0.5, f32(int(path[k]) / WORLD_SIZE) + 0.5
			if clear_line(g, g.ship.x, g.ship.y, px, py, avoid) {
				tx, ty = px, py
				break
			}
		}
		if tx == g.ship.x && ty == g.ship.y { 	// nothing in sight (should not happen): the next tile
			last := path[n - 1]
			tx, ty = f32(int(last) % WORLD_SIZE) + 0.5, f32(int(last) / WORLD_SIZE) + 0.5
		}
	}
	dx, dy := tx - g.ship.x, ty - g.ship.y
	run = math.sqrt(dx * dx + dy * dy)
	if run < 0.001 {return g.ship.heading, 0, true}
	deg := math.atan2(dx, -dy) * 180 / math.PI
	return wrap_heading(int(math.round(deg))), run, true
}

// True when a straight run between two points stays on water (sampled every tenth of a tile, both sides of the line).
clear_line :: proc(g: ^Game, x0, y0, x1, y1: f32, avoid_storms := false) -> bool {
	dx, dy := x1 - x0, y1 - y0
	length := math.sqrt(dx * dx + dy * dy)
	steps := max(1, int(length * 10))
	// The ship moves along the rounded heading, so allow a little width either side.
	ox, oy := f32(0), f32(0)
	if length > 0 {ox, oy = -dy / length * 0.15, dx / length * 0.15}
	for s in 0 ..= steps {
		t := f32(s) / f32(steps)
		x, y := x0 + dx * t, y0 + dy * t
		for side in ([3]f32{0, 1, -1}) {
			px, py := x + ox * side, y + oy * side
			if px < 0 || py < 0 || px >= WORLD_SIZE || py >= WORLD_SIZE || is_land(g, int(px), int(py)) {return false}
			if avoid_storms && stormy(g, px, py) {return false}
		}
	}
	return true
}

// True when a point is in or close to a storm the ship can see: a course keeps clear of these.
stormy :: proc(g: ^Game, x, y: f32) -> bool {
	for k in 0 ..< g.n_storms {
		st := g.storms[k]
		if !st.seen || !storm_in_view(g, k) {continue}
		dx, dy := x - st.x, y - st.y
		reach := st.radius + 0.75
		if dx * dx + dy * dy <= reach * reach {return true}
	}
	return false
}

// True when the course's island is in docking range.
arrived :: proc(g: ^Game) -> bool {
	near: [ISLAND_MAX]int
	n := dockable(g, near[:])
	for j in 0 ..< n {if near[j] == g.course {return true}}
	return false
}
