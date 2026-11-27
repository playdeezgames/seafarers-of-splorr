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
	// The same, word-wrapped to width w; returns the baseline after the last line.
	draw_text_wrapped :: proc(x, y, w: f32, text: string, rgb: u32) -> f32 ---
	play_sound :: proc(sound: i32) ---
	// Writes the save bytes to localStorage.
	store_save :: proc(data: []u8) ---
	// Flips the page's mute setting and returns the new value.
	toggle_mute :: proc() -> bool ---
	// Removes the stored voyage (it ended).
	clear_save :: proc() ---
	// The best retirement score kept in localStorage.
	store_best :: proc(score: i32) ---
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
PAPER :: 0xe8dcb8
INK :: 0x3a2a18
INK_DIM :: 0x7a6a50
LATE :: 0xa02a1a
RED :: 0xe0533a
LAND :: 0xb4532a

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
boot :: proc "c" (seed_hi, seed_lo: i32, seeded, muted: bool, save_len: i32, best: i32) {
	context = ctx
	hi := u64(u32(seed_hi))
	lo := u64(u32(seed_lo))
	state.muted = muted
	if best >= 0 {state.best, state.has_best = int(best), true}
	game.title(&state, hi << 32 | lo)
	qa = seeded
	if !qa && save_len > 0 {
		err := game.Load_Error.Size // longer than the buffer: the page wrote only its first bytes
		if int(save_len) <= len(load_buf) {err = game.save_decode(&state, load_buf[:save_len])}
		if err == .Version {
			game.logf(&state, "Old save: the sea")
			game.logf(&state, "has changed. Sorry!")
		} else if err != .None {
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
			if g.has_voyage {
				buf: [game.SAVE_SIZE]u8
				game.save_encode(g, &buf)
				store_save(buf[:])
			} else {
				clear_save()
			}
		}
		g.want_save = false
	}
	if g.want_best {
		if !qa {store_best(i32(g.best))}
		g.want_best = false
	}
	for i in 0 ..< g.n_sounds {play_sound(i32(g.sounds[i]))}
	g.n_sounds = 0
	draw(g)
	return true
}

draw :: proc(g: ^game.Game) {
	if g.screen == .Sea && g.sub == .Chart {
		draw_chart(g)
	} else if g.screen == .Sea && g.sub == .Book {
		fill_rect(0, 0, game.PANEL_X, game.LOGICAL_H, DEEP, 1)
		draw_book(g, g.book_good, 16)
	} else {
		draw_sea(g)
		if g.screen == .Sea || g.screen == .Docked {draw_hud(g)}
		if g.screen == .Docked && (g.sub == .Offer || g.sub == .Carried_Detail) {draw_letter(g)}
		if g.screen == .Docked && g.sub == .Trade && g.trade_good != game.RATIONS {
			fill_rect(0, 48, game.PANEL_X, game.LOGICAL_H - 48, DEEP, 0.88)
			draw_book(g, game.Good(g.trade_good), 64)
		}
	}
	draw_panel(g)
}

// Coastline tiles from the Bountiful Bits Natural sheet, by land_mask (1 north, 2 east, 4 south, 8 west). Islands are
// built so only these nine masks occur; anything else falls back to the lone patch.
coast_tile :: proc(mask, h: int) -> (col, row: i32) {
	switch mask {
	case 6: return 17, 11 // north-west corner
	case 12: return 18, 11 // north-east corner
	case 3: return 16, 14 // south-west corner
	case 9: return 20, 13 // south-east corner
	case 7: return 17, 12 // west shore
	case 14: return 19, 12 // north shore
	case 11: return 17, 14 // south shore
	case 13: return 19, 14 // east shore
	case 15:
		INNER := [5][2]i32{{18, 13}, {17, 13}, {19, 13}, {18, 12}, {18, 14}}
		v := INNER[h % 5]
		return v.x, v.y
	}
	return 14, 10
}

// The sea view: the ship stays in the centre and the world scrolls under it. Beyond the view distance the sea is hazed
// and only charted islands show.
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
			if i := game.land_at(g, tx, ty); i != game.NO_ISLAND && g.islands[i].charted {
				mask := game.land_mask(g, tx, ty)
				c, r := coast_tile(mask, h)
				draw_tile(c, r, px, py)
				if mask == 15 && h % 3 == 0 {draw_tile(i32(22 + h / 3 % 6), 1, px, py)} // a tree
			}
			dx, dy := f32(tx) + 0.5 - g.ship.x, f32(ty) + 0.5 - g.ship.y
			if dx * dx + dy * dy > game.VIEW_DISTANCE * game.VIEW_DISTANCE {fill_rect(px, py, T, T, DEEP, 0.4)}
		}
	}
	draw_ship(half * T, half * T, f32(g.ship.heading))
}

// The whole world at two pixels a tile: charted land, the ship and its view.
draw_chart :: proc(g: ^game.Game) {
	S :: f32(2)
	fill_rect(0, 0, game.PANEL_X, game.LOGICAL_H, SEA, 1)
	for ty in 0 ..< game.WORLD_SIZE {
		for tx in 0 ..< game.WORLD_SIZE {
			if i := game.land_at(g, tx, ty); i != game.NO_ISLAND && g.islands[i].charted {
				fill_rect(f32(tx) * S, f32(ty) * S, S, S, game.is_destination(g, i) ? GOLD : LAND, 1)
			}
		}
	}
	sx, sy := g.ship.x * S, g.ship.y * S
	r := f32(game.VIEW_DISTANCE) * S
	fill_rect(sx - r, sy - r, 2 * r, 1, WHITE, 0.25)
	fill_rect(sx - r, sy + r, 2 * r, 1, WHITE, 0.25)
	fill_rect(sx - r, sy - r, 1, 2 * r, WHITE, 0.25)
	fill_rect(sx + r, sy - r, 1, 2 * r, WHITE, 0.25)
	fill_rect(math.round(sx) - 1, math.round(sy) - 1, 3, 3, WHITE, 1)
}

// The price book for one good: every island you have docked at that trades it, dearest first, with what it asked
// (Buy), what it would pay (Sell) and how long ago you saw it.
draw_book :: proc(g: ^game.Game, good: game.Good, y0: f32) {
	buf: [48]u8
	draw_text(8, y0, fmt.bprintf(buf[:], "%s: prices seen", game.GOODS[good].name), GOLD, 1, false)
	y := y0 + f32(game.LINE) + 2
	draw_text(8, y, "Island", DIM, 1, false)
	draw_text(104, y, "Buy", DIM, 1, false)
	draw_text(140, y, "Sell", DIM, 1, false)
	draw_text(180, y, "Seen", DIM, 1, false)
	fill_rect(6, y + 3, game.PANEL_X - 12, 1, EDGE, 1)
	rows: [game.ISLAND_MAX]int
	n := game.book_rows(g, good, rows[:])
	if n == 0 {
		draw_text(8, y + f32(game.LINE) + 2, "None seen yet: dock", WHITE, 1, false)
		draw_text(8, y + 2 * f32(game.LINE) + 2, "where it is traded.", WHITE, 1, false)
		return
	}
	for k in 0 ..< n {
		y += f32(game.LINE)
		if y > game.LOGICAL_H - 4 {break}
		i := rows[k]
		seen := g.seen[i]
		here := i == g.docked
		colour: u32 = here ? GOLD : WHITE
		draw_text(8, y, game.island_name(g, i), colour, 1, false)
		draw_text(104, y, fmt.bprintf(buf[:], "%d", seen.price[good]), colour, 1, false)
		draw_text(140, y, fmt.bprintf(buf[:], "%d", game.paid_for(seen.price[good])), colour, 1, false)
		age := g.turn - seen.turn
		draw_text(180, y, age == 0 ? "now" : fmt.bprintf(buf[:], "%d ago", age), age > 200 ? FAINT : DIM, 1, false)
	}
}

// A delivery shown as a letter over the sea view.
draw_letter :: proc(g: ^game.Game) {
	d: game.Delivery
	if g.sub == .Offer {
		if g.pick >= g.n_offers {return}
		d = g.offers[g.pick]
	} else {
		if g.pick >= g.n_carried {return}
		d = g.carried[g.pick]
	}
	X, Y, W, H :: 16, 62, 208, 104
	fill_rect(X + 3, Y + 3, W, H, 0x000000, 0.4)
	fill_rect(X, Y, W, H, PAPER, 1)
	fill_rect(X, Y, W, 1, INK_DIM, 1)
	fill_rect(X, Y + H - 1, W, 1, INK_DIM, 1)
	buf: [200]u8
	y := draw_text_wrapped(X + 8, Y + 16, W - 16, game.delivery_text(g, d, buf[:]), INK)
	lb: [64]u8
	y += 6
	draw_text(X + 8, y, fmt.bprintf(lb[:], "From %s, %d leagues.", game.island_name(g, d.from), game.leagues_between(g, d.from, d.to)), INK_DIM, 1, false)
	y += f32(game.LINE)
	left := d.due - g.turn
	if left >= 0 {
		draw_text(X + 8, y, fmt.bprintf(lb[:], "Pays %d by turn %d (%d left).", d.reward, d.due, left), INK, 1, false)
	} else {
		draw_text(X + 8, y, fmt.bprintf(lb[:], "Late! Now pays %d.", game.pay_for(g, d)), LATE, 1, false)
	}
}

// Ship's condition along the top of the sea view.
draw_hud :: proc(g: ^game.Game) {
	fill_rect(0, 0, game.PANEL_X, 45, DEEP, 0.7)
	buf: [48]u8
	food: u32 = g.rations == 0 ? RED : (g.rations < 100 ? GOLD : WHITE)
	draw_text(4, 12, fmt.bprintf(buf[:], "Food %d", g.rations), food, 1, false)
	draw_text(84, 12, fmt.bprintf(buf[:], "Fed %d", g.satiety), g.satiety < 50 ? GOLD : WHITE, 1, false)
	draw_text(150, 12, fmt.bprintf(buf[:], "Health %d", g.health), g.health < 50 ? RED : WHITE, 1, false)
	p, sb := game.hull_clean(g, .Port), game.hull_clean(g, .Starboard)
	draw_text(4, 26, fmt.bprintf(buf[:], "Hull: port %d%%, starboard %d%%", p, sb), min(p, sb) < 60 ? GOLD : DIM, 1, false)
	draw_text(4, 40, fmt.bprintf(buf[:], "Money %d", g.money), GOLD, 1, false)
	used := game.hold_used(g)
	draw_text(110, 40, fmt.bprintf(buf[:], "Hold %d/%d", used, game.HOLD_TONS), used >= game.HOLD_TONS ? GOLD : WHITE, 1, false)
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
	case .Over:
		if g.outcome == .Retired {
			draw_text(tx, 14, "RETIRED", GOLD, 1, false)
			draw_text(tx, 28, fmt.bprintf(buf[:], "Net worth %d", game.score(g)), WHITE, 1, false)
			if g.new_best {
				draw_text(tx, 42, "A new best!", GOLD, 1, false)
			} else {
				draw_text(tx, 42, fmt.bprintf(buf[:], "Best %d", g.best), DIM, 1, false)
			}
		} else {
			draw_text(tx, 14, "LOST AT SEA", RED, 1, false)
			draw_text(tx, 28, fmt.bprintf(buf[:], "On turn %d", g.turn), WHITE, 1, false)
			if g.has_best {draw_text(tx, 42, fmt.bprintf(buf[:], "Best %d", g.best), DIM, 1, false)}
		}
	case .Docked:
		#partial switch g.sub {
		case .Deliveries, .Offer, .Carried, .Carried_Detail:
			draw_text(tx, 14, "Delivery service", GOLD, 1, false)
			draw_text(tx, 28, fmt.bprintf(buf[:], "Carrying %d of %d", g.n_carried, game.CARRY_MAX), WHITE, 1, false)
			draw_text(tx, 42, fmt.bprintf(buf[:], "Delivered %d so far", g.deliveries_made), DIM, 1, false)
		case .Vendor:
			draw_text(tx, 14, "Street vendor", GOLD, 1, false)
			draw_text(tx, 28, fmt.bprintf(buf[:], "Money %d", g.money), WHITE, 1, false)
			draw_text(tx, 42, fmt.bprintf(buf[:], "%d lots left today", g.vendor_stock), DIM, 1, false)
		}
		if g.sub == .Deliveries || g.sub == .Offer || g.sub == .Carried || g.sub == .Carried_Detail || g.sub == .Vendor {break}
		if g.sub == .Market || g.sub == .Trade {
			draw_text(tx, 14, fmt.bprintf(buf[:], "Money %d", g.money), GOLD, 1, false)
			draw_text(tx, 28, fmt.bprintf(buf[:], "Hold %d of %d tons", game.hold_used(g), game.HOLD_TONS), WHITE, 1, false)
			if g.sub == .Market {
				draw_text(tx, 42, "Price: buy / sell", DIM, 1, false)
			} else if g.trade_good == game.RATIONS {
				draw_text(tx, 42, fmt.bprintf(buf[:], "Rations: %d", g.rations), WHITE, 1, false)
			} else {
				good := game.Good(g.trade_good)
				draw_text(tx, 42, fmt.bprintf(buf[:], "%s: %d aboard", game.GOODS[good].name, g.cargo[good]), WHITE, 1, false)
			}
			break
		}
		draw_text(tx, 14, fmt.bprintf(buf[:], "Turn %d of %d", g.turn, game.TURN_LIMIT), WHITE, 1, false)
		draw_text(tx, 28, "Docked at", DIM, 1, false)
		if g.docked != game.NO_ISLAND {draw_text(tx, 42, game.island_name(g, g.docked), GOLD, 1, false)}
	case .Sea:
		draw_text(tx, 14, fmt.bprintf(buf[:], "Turn %d of %d", g.turn, game.TURN_LIMIT), WHITE, 1, false)
		if g.sub == .Book {
			draw_text(tx, 28, "The price book", GOLD, 1, false)
			draw_text(tx, 42, "Turns since seen", DIM, 1, false)
		} else if g.sub == .Chart {
			n := 0
			for i in 0 ..< g.n_islands {if g.islands[i].charted {n += 1}}
			draw_text(tx, 28, "The chart", GOLD, 1, false)
			draw_text(tx, 42, fmt.bprintf(buf[:], "%d of %d islands", n, g.n_islands), DIM, 1, false)
		} else {
			draw_text(tx, 28, fmt.bprintf(buf[:], "Heading %03d %s", g.ship.heading, game.compass(g.ship.heading)), WHITE, 1, false)
			eff := int(game.effective_speed(g) + 0.5)
			speed := g.ship.speed == 0 ? "All stop" : (eff < g.ship.speed ? fmt.bprintf(buf[:], "Speed %d%% (%d)", g.ship.speed, eff) : fmt.bprintf(buf[:], "Speed %d%%", g.ship.speed))
			draw_text(tx, 42, speed, WHITE, 1, false)
		}
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
