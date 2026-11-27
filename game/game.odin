// Rules and state for Seafarers of SPLORR!!. No browser code here: the web layer in src/web draws and feeds input.
package game

import "core:fmt"
import "core:math"

LOGICAL_W :: 400
LOGICAL_H :: 240
TILE :: 10 // Bountiful Bits tiles are 10 by 10
VIEW_TILES :: 24 // the sea view is 24 by 24 tiles on the left
PANEL_X :: 240 // the menu panel fills the rest
LINE :: 14 // m6x11 line height
MENU_Y :: 64 // baseline of the first menu line
MENU_MAX :: 7
LOG_LINES :: 4
LOG_Y :: LOGICAL_H - 4 - (LOG_LINES - 1) * LINE // baseline of the oldest log line
LOG_LEN :: 40

WORLD_SIZE :: 100 // world is WORLD_SIZE by WORLD_SIZE tiles (a placeholder until phase 1)
ISLAND_MAX :: 40
ISLAND_GAP :: 8 // Classic's minimum distance between islands
TURN_MAX :: 1_000_000

Screen :: enum u8 {
	Title,
	Sea,
}

// Keyboard and gamepad commands; order matches ACTION in web/index.html.
Action :: enum i32 {
	Up,
	Down,
	Confirm,
	Back,
}

// Sound effects; order matches SOUNDS in web/index.html.
Sound :: enum u8 {
	Move,
	Select,
	Deny,
}

Cmd :: enum u8 {
	New_Voyage,
	Continue,
	Sound_Toggle,
	Port,
	Starboard,
	Sail,
	To_Title,
}

Item :: struct {
	label: string,
	cmd:   Cmd,
}

Menu :: struct {
	items: [MENU_MAX]Item,
	n:     int,
}

Ship :: struct {
	x, y:    f32, // true position in tiles; the centre of tile (tx, ty) is (tx + 0.5, ty + 0.5)
	heading: int, // degrees, 0 is north, clockwise, 0 ..< 360
	speed:   int, // percent of full sail, 0 ..= 100
}

Island :: struct {
	x, y: int,
}

Game :: struct {
	seed:       u64,
	next_seed:  u64, // the world New voyage builds; ?seed=N sets it for QA
	rng:        Rng,
	screen:     Screen,
	turn:       int,
	ship:       Ship,
	islands:    [ISLAND_MAX]Island,
	n_islands:  int,
	cursor:     int,
	has_voyage: bool, // a voyage exists (started or loaded) that Continue returns to
	muted:      bool, // mirrors the page's mute setting, for the menu label
	// Requests to the web layer, cleared by it.
	want_save:  bool,
	want_mute:  bool,
	sounds:     [8]Sound,
	n_sounds:   int,
	log:        [LOG_LINES][LOG_LEN]u8,
	log_len:    [LOG_LINES]int,
}

// A fresh game on the title screen; the world comes from seed.
title :: proc(g: ^Game, seed: u64) {
	g^ = {}
	g.next_seed = seed
	start_world(g, seed)
	logf(g, "Welcome aboard.")
}

start_world :: proc(g: ^Game, seed: u64) {
	g.seed = seed
	g.rng = rng_make(seed)
	generate_islands(g)
	g.ship = {x = WORLD_SIZE / 2 + 0.5, y = WORLD_SIZE / 2 + 0.5, heading = 0, speed = 100}
}

// Islands placed at random with a minimum gap (Classic's rule). Uses its own generator so the world depends only on
// the seed, not on play: a save needs to store only the seed to rebuild it.
generate_islands :: proc(g: ^Game) {
	r := rng_make(g.seed ~ 0x15_1A_4D_5E_ED)
	g.n_islands = 0
	centre := WORLD_SIZE / 2
	for _ in 0 ..< 2000 {
		if g.n_islands == ISLAND_MAX {break}
		x := 2 + rng_below(&r, WORLD_SIZE - 4)
		y := 2 + rng_below(&r, WORLD_SIZE - 4)
		if abs(x - centre) < 3 && abs(y - centre) < 3 {continue} // keep the starting tile clear
		ok := true
		for i in 0 ..< g.n_islands {
			dx, dy := g.islands[i].x - x, g.islands[i].y - y
			if dx * dx + dy * dy < ISLAND_GAP * ISLAND_GAP {
				ok = false
				break
			}
		}
		if ok {
			g.islands[g.n_islands] = {x, y}
			g.n_islands += 1
		}
	}
}

is_land :: proc(g: ^Game, tx, ty: int) -> bool {
	for i in 0 ..< g.n_islands {
		if g.islands[i].x == tx && g.islands[i].y == ty {return true}
	}
	return false
}

menu :: proc(g: ^Game) -> (m: Menu) {
	add :: proc(m: ^Menu, label: string, cmd: Cmd) {
		m.items[m.n] = {label, cmd}
		m.n += 1
	}
	switch g.screen {
	case .Title:
		if g.has_voyage {add(&m, "Continue voyage", .Continue)}
		add(&m, "New voyage", .New_Voyage)
		add(&m, g.muted ? "Sound: off" : "Sound: on", .Sound_Toggle)
	case .Sea:
		add(&m, "Turn to port", .Port)
		add(&m, "Turn to starboard", .Starboard)
		add(&m, "Sail one league", .Sail)
		add(&m, g.muted ? "Sound: off" : "Sound: on", .Sound_Toggle)
		add(&m, "Back to title", .To_Title)
	}
	return
}

input :: proc(g: ^Game, a: Action) {
	m := menu(g)
	g.cursor = clamp(g.cursor, 0, max(m.n - 1, 0))
	switch a {
	case .Up:
		g.cursor = (g.cursor + m.n - 1) % m.n
		sound(g, .Move)
	case .Down:
		g.cursor = (g.cursor + 1) % m.n
		sound(g, .Move)
	case .Confirm:
		choose(g, g.cursor)
	case .Back:
		if g.screen == .Sea {
			do_cmd(g, .To_Title)
		} else {
			sound(g, .Deny)
		}
	}
}

// Pick menu item i (a number key, a tap or Confirm).
choose :: proc(g: ^Game, i: int) {
	m := menu(g)
	if i < 0 || i >= m.n {
		sound(g, .Deny)
		return
	}
	g.cursor = i
	do_cmd(g, m.items[i].cmd)
}

click :: proc(g: ^Game, x, y: int) {
	if x < PANEL_X {return}
	m := menu(g)
	for i in 0 ..< m.n {
		base := MENU_Y + i * LINE
		if y > base - LINE + 2 && y <= base + 2 {
			choose(g, i)
			return
		}
	}
}

do_cmd :: proc(g: ^Game, cmd: Cmd) {
	sound(g, .Select)
	switch cmd {
	case .New_Voyage:
		seed := g.next_seed
		start_world(g, seed)
		g.next_seed = rng_next(&g.rng)
		g.turn = 0
		g.screen = .Sea
		g.has_voyage = true
		g.cursor = 0
		logf(g, "A new voyage begins.")
		g.want_save = true
	case .Continue:
		g.screen = .Sea
		g.cursor = 0
	case .Sound_Toggle:
		g.want_mute = true
	case .Port:
		g.ship.heading = wrap_heading(g.ship.heading - 45)
		logf(g, "Heading %03d %s.", g.ship.heading, compass(g.ship.heading))
		g.want_save = true
	case .Starboard:
		g.ship.heading = wrap_heading(g.ship.heading + 45)
		logf(g, "Heading %03d %s.", g.ship.heading, compass(g.ship.heading))
		g.want_save = true
	case .Sail:
		sail(g)
		g.want_save = true
	case .To_Title:
		g.screen = .Title
		g.cursor = 0
	}
}

// Move one tile along the heading, scaled by speed. Stops at the edge of the world and refuses to sail onto land.
sail :: proc(g: ^Game) {
	rad := f32(g.ship.heading) * math.PI / 180
	step := f32(g.ship.speed) / 100
	nx := g.ship.x + math.sin(rad) * step
	ny := g.ship.y - math.cos(rad) * step
	if nx < 0 || ny < 0 || nx >= WORLD_SIZE || ny >= WORLD_SIZE {
		sound(g, .Deny)
		logf(g, "The edge of the charts.")
		return
	}
	if is_land(g, int(nx), int(ny)) {
		sound(g, .Deny)
		logf(g, "Land ahead!")
		return
	}
	g.ship.x, g.ship.y = nx, ny
	g.turn += 1
	logf(g, "Turn %d: sailed %s.", g.turn, compass(g.ship.heading))
}

wrap_heading :: proc(h: int) -> int {
	return ((h % 360) + 360) % 360
}

compass :: proc(h: int) -> string {
	NAMES := [8]string{"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
	return NAMES[((wrap_heading(h) + 22) / 45) % 8]
}

sound :: proc(g: ^Game, s: Sound) {
	if g.n_sounds < len(g.sounds) {
		g.sounds[g.n_sounds] = s
		g.n_sounds += 1
	}
}

// Add a line to the message log, dropping the oldest. Lines longer than LOG_LEN are cut.
logf :: proc(g: ^Game, format: string, args: ..any) {
	for i in 0 ..< LOG_LINES - 1 {
		g.log[i] = g.log[i + 1]
		g.log_len[i] = g.log_len[i + 1]
	}
	s := fmt.bprintf(g.log[LOG_LINES - 1][:], format, ..args)
	g.log_len[LOG_LINES - 1] = len(s)
}

log_line :: proc(g: ^Game, i: int) -> string {
	return string(g.log[i][:g.log_len[i]])
}
