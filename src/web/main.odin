// Thin browser layer: input, drawing and the frame loop. Rules and state live in package game.
#+build js
package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "sos:game"

foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	// rgb is 0xRRGGBB; coordinates are logical pixels, y down.
	fill_rect :: proc(x, y, w, h: f32, rgb: u32, alpha: f32) ---
	// One 10 by 10 tile of the Bountiful Bits Natural sheet (col, row) at x, y.
	draw_tile :: proc(col, row: i32, x, y: f32) ---
	// The ship, centred on x, y, turned to heading degrees (0 north, clockwise).
	draw_ship :: proc(x, y, heading: f32) ---
	// Bitmap text (m6x11). y is the baseline; scale is a whole number; x is the centre when centered.
	draw_text :: proc(x, y: f32, text: string, rgb: u32, scale: i32, centered: bool) ---
	play_sound :: proc(sound: i32) ---
	// Writes the save bytes to localStorage.
	store_save :: proc(data: []u8) ---
	// Flips the page's mute setting and returns the new value.
	toggle_mute :: proc() -> bool ---
}

WHITE :: 0xf4ecd8
DIM :: 0x8a9ab0
FAINT :: 0x5a6a80
GOLD :: 0xf5c542
SEA :: 0x24508a
SEA_FLECK :: 0x3a6aa8
DEEP :: 0x0e1a2e
PANEL :: 0x141c2a
EDGE :: 0x3a4a62
HILITE :: 0x2a3a58

ctx: runtime.Context
state: game.Game
booted: bool
qa: bool // ?seed=N: a repeatable world that neither loads nor overwrites the real save
load_buf: [game.SAVE_SIZE]u8

main :: proc() {
	ctx = context
}

// Where the page writes a stored save before calling boot.
@(export)
save_buffer :: proc "c" () -> rawptr {
	return &load_buf
}

@(export)
save_size :: proc "c" () -> i32 {
	return game.SAVE_SIZE
}

// Called once by the page after the wasm is running. seed_hi and seed_lo make the world seed; seeded is true for
// ?seed=N. save_len is the number of bytes the page wrote into save_buffer (0 when there is no save).
@(export)
boot :: proc "c" (seed_hi, seed_lo: i32, seeded, muted: bool, save_len: i32) {
	context = ctx
	hi := u64(u32(seed_hi))
	lo := u64(u32(seed_lo))
	game.title(&state, hi << 32 | lo)
	state.muted = muted
	qa = seeded
	if !qa && save_len > 0 {
		err := game.Load_Error.Size // longer than the buffer: the page wrote only its first bytes
		if int(save_len) <= len(load_buf) {err = game.save_decode(&state, load_buf[:save_len])}
		if err != .None {
			game.logf(&state, "Bad save (%v).", err)
		} else {
			game.logf(&state, "Voyage restored.")
		}
	}
	if qa {game.logf(&state, "QA seed %d.", hi << 32 | lo)}
	booted = true
}

@(export)
input :: proc "c" (action: i32) {
	context = ctx
	if !booted || action < 0 || action > i32(max(game.Action)) {return}
	game.input(&state, game.Action(action))
}

// Number keys: pick menu item i (0-based).
@(export)
pick :: proc "c" (i: i32) {
	context = ctx
	if booted {game.choose(&state, int(i))}
}

@(export)
click :: proc "c" (x, y: i32) {
	context = ctx
	if booted {game.click(&state, int(x), int(y))}
}

// The page's M key flips mute itself and tells the game, so the menu label follows.
@(export)
set_muted :: proc "c" (muted: bool) {
	context = ctx
	state.muted = muted
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	if !booted {return true}
	g := &state
	if g.want_mute {
		g.muted = toggle_mute()
		g.want_mute = false
	}
	if g.want_save {
		if !qa {
			buf: [game.SAVE_SIZE]u8
			game.save_encode(g, &buf)
			store_save(buf[:])
		}
		g.want_save = false
	}
	for i in 0 ..< g.n_sounds {play_sound(i32(g.sounds[i]))}
	g.n_sounds = 0
	draw(g)
	return true
}

draw :: proc(g: ^game.Game) {
	draw_sea(g)
	draw_panel(g)
}

// The sea view: the ship stays in the centre and the world scrolls under it.
draw_sea :: proc(g: ^game.Game) {
	T :: f32(game.TILE)
	half := f32(game.VIEW_TILES) / 2
	fx := g.ship.x - half // world tile at the view's left edge (fractional)
	fy := g.ship.y - half
	tx0, ty0 := int(math.floor(fx)), int(math.floor(fy))
	for ty in ty0 ..= ty0 + game.VIEW_TILES {
		for tx in tx0 ..= tx0 + game.VIEW_TILES {
			px := math.round((f32(tx) - fx) * T)
			py := math.round((f32(ty) - fy) * T)
			inside := tx >= 0 && ty >= 0 && tx < game.WORLD_SIZE && ty < game.WORLD_SIZE
			if !inside {
				fill_rect(px, py, T, T, DEEP, 1)
				continue
			}
			fill_rect(px, py, T, T, SEA, 1)
			h := tile_hash(tx, ty)
			if h % 5 == 0 {fill_rect(px + f32(h / 5 % 7), py + f32(h / 35 % 8), 3, 1, SEA_FLECK, 1)}
			if game.is_land(g, tx, ty) {draw_tile(14, 10, px, py)} // a lone patch of ground; coastlines come in phase 1
		}
	}
	draw_ship(half * T, half * T, f32(g.ship.heading))
}

tile_hash :: proc(x, y: int) -> int {
	h := u32(x) * 73856093 ~ u32(y) * 19349663
	h ~= h >> 13
	h *= 0x5bd1e995
	return int(h >> 8 & 0xffff)
}

draw_panel :: proc(g: ^game.Game) {
	x0 := f32(game.PANEL_X)
	fill_rect(x0, 0, game.LOGICAL_W - x0, game.LOGICAL_H, PANEL, 1)
	fill_rect(x0, 0, 1, game.LOGICAL_H, EDGE, 1)
	tx := x0 + 6
	buf: [48]u8

	switch g.screen {
	case .Title:
		draw_text(x0 + 80, 18, "SEAFARERS", GOLD, 1, true)
		draw_text(x0 + 80, 32, "of SPLORR!!", WHITE, 1, true)
		draw_text(x0 + 80, 46, "sail, trade, retire", DIM, 1, true)
	case .Sea:
		draw_text(tx, 14, fmt.bprintf(buf[:], "Turn %d", g.turn), WHITE, 1, false)
		draw_text(tx, 28, fmt.bprintf(buf[:], "Heading %03d %s", g.ship.heading, game.compass(g.ship.heading)), WHITE, 1, false)
		draw_text(tx, 42, fmt.bprintf(buf[:], "Speed %d%%", g.ship.speed), WHITE, 1, false)
	}
	fill_rect(x0 + 4, game.MENU_Y - game.LINE - 2, game.LOGICAL_W - x0 - 8, 1, EDGE, 1)

	m := game.menu(g)
	for i in 0 ..< m.n {
		y := f32(game.MENU_Y + i * game.LINE)
		on := i == g.cursor
		if on {fill_rect(x0 + 3, y - 11, game.LOGICAL_W - x0 - 6, game.LINE, HILITE, 1)}
		draw_text(tx, y, fmt.bprintf(buf[:], "%d", i + 1), on ? GOLD : FAINT, 1, false)
		draw_text(tx + 12, y, m.items[i].label, on ? GOLD : WHITE, 1, false)
	}

	fill_rect(x0 + 4, game.LOG_Y - game.LINE + 1, game.LOGICAL_W - x0 - 8, 1, EDGE, 1)
	for i in 0 ..< game.LOG_LINES {
		draw_text(tx, f32(game.LOG_Y + i * game.LINE), game.log_line(g, i), i == game.LOG_LINES - 1 ? WHITE : DIM, 1, false)
	}
}
