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
MENU_MAX :: 9 // number keys 1 to 9
MENU_TEXT :: 24
LOG_LINES :: 4
LOG_Y :: LOGICAL_H - 4 - (LOG_LINES - 1) * LINE // baseline of the oldest log line
LOG_LEN :: 40

Screen :: enum u8 {
	Title,
	Start, // choosing the captain (Phase 6)
	Sea,
	Docked,
	Over, // retired or dead: the score
}

// A submenu open over the sea screen.
Sub :: enum u8 {
	None,
	Heading,
	Adjust,
	Speed,
	Sail,
	Head_For,
	Dock,
	Chart,
	Careen,
	Market, // the goods this island trades, and rations
	Trade, // buy or sell one good (g.trade_good)
	Deliveries, // the delivery service: offers, and what you carry
	Offer, // one offer (g.pick), shown as a letter
	Carried, // the deliveries aboard
	Carried_Detail, // one carried delivery (g.pick)
	Vendor, // the street vendor
	Book, // the price book for g.book_good, opened from the chart
	Alley, // the dark alley's card table
	Custom, // spending a custom captain's points (on the Start screen)
	Crew, // the crew list
	Member, // one crew member (g.pick)
	Tavern, // sailors for hire
	Candidate, // one sailor for hire (g.pick)
	Logbook, // the captain's log, opened from the chart
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
	Sighted,
	Dock,
	Retire,
	Lose,
	Coins,
	Deal,
	Win,
	Bust,
	Bell,
}

Cmd :: enum u8 {
	New_Voyage,
	Continue,
	Sound_Toggle,
	To_Title,
	Open, // arg: Sub
	Back,
	Set_Heading, // arg: degrees
	Adjust, // arg: degrees to add
	Set_Speed, // arg: percent
	Sail, // arg: turns
	Head_For, // arg: island
	Dock, // arg: island, or NO_ISLAND to dock at the only one in range or choose
	Undock,
	Careen, // arg: Side
	Pick_Good, // arg: Good, or RATIONS
	Buy, // arg: how many (a large number for "max")
	Sell, // arg: how many (a large number for "all")
	Pick_Offer, // arg: offer index
	Accept,
	Pick_Carried, // arg: carried index
	Abandon,
	Vendor_Buy, // arg: lots
	Book_Step, // arg: +1 or -1 through the goods
	Deal,
	Bet, // arg: times the minimum stake
	Fold,
	Next_Page, // Head for: the next page of islands
	Begin, // arg: Profession, or QUICK
	Spend, // arg: Skill, a custom captain's next SKILL_STEP points
	Pick_Member, // arg: crew index
	Dismiss,
	Fish,
	Pick_Candidate, // arg: candidate index
	Hire,
	Log_Page, // the captain's log: the next page
}

HEAD_FOR_PAGE :: MENU_MAX - 2 // islands a page when they do not all fit: leaves room for More and Back

RATIONS :: -1 // Pick_Good's arg for the rations stall
ALL :: 1_000_000 // Buy and Sell's arg for "as many as possible"


Item :: struct {
	label: string,
	cmd:   Cmd,
	arg:   int,
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

Game :: struct {
	seed:       u64,
	next_seed:  u64, // the world New voyage builds; ?seed=N sets it for QA
	rng:        Rng,
	screen:     Screen,
	sub:        Sub,
	turn:       int,
	ship:       Ship,
	docked:     int, // island index, or NO_ISLAND at sea
	islands:    [ISLAND_MAX]Island,
	n_islands:  int,
	land:       [WORLD_SIZE * WORLD_SIZE]u8, // 0 water, else island index + 1
	cursor:     int,
	has_voyage: bool, // a voyage exists (started or loaded) that Continue returns to
	money:      int,
	rations:    int,
	satiety:    int,
	health:     int,
	foul:       [Side]int, // ten-thousandths, 0 ..= FOUL_MAX
	outcome:    Outcome,
	best:       int, // best retirement score on this browser
	has_best:   bool,
	new_best:   bool,
	want_best:  bool,
	cargo:      [Good]int,
	markets:    [ISLAND_MAX]Market, // current, saved
	usual:      [ISLAND_MAX]Market, // from the seed: where markets drift back to
	trades:     [ISLAND_MAX]bit_set[Good], // from the seed
	trade_good: int, // the good open in the Trade submenu, or RATIONS
	districts:  [ISLAND_MAX]bit_set[District], // from the seed
	offers:     [OFFERS_MAX]Delivery, // at the docked island's delivery service
	n_offers:   int,
	carried:    [CARRY_MAX]Delivery,
	n_carried:  int,
	deliveries_made: int,
	vendor_stock: int, // lots left at the docked island's street vendor
	pick:       int, // the offer or carried delivery open in a submenu
	seen:       [ISLAND_MAX]Seen, // the price book
	book_good:  Good,
	stakes:     [ISLAND_MAX]int, // the dark alley's minimum stake, from the seed
	hand:       [3]int,
	hand_state: Hand_State,
	hand_won:   bool,
	bet:        int,
	page:       int, // Head for page
	crew:       [CREW_MAX]Member, // crew[0] is the captain
	n_crew:     int,
	candidates: [CANDIDATES_MAX]Member, // at the docked island's tavern
	n_candidates: int,
	wage_turns: int, // turns since wages were last paid
	logbook:    [LOGBOOK_MAX]Log_Entry,
	n_logbook:  int,
	log_page:   int,
	spent:      [Skill]int, // a custom captain's points, while choosing
	palmed:     bool, // the last alley hand's third card was swapped
	muted:      bool, // mirrors the page's mute setting, for the menu label
	// Requests to the web layer, cleared by it.
	want_save:  bool,
	want_mute:  bool,
	sounds:     [8]Sound,
	n_sounds:   int,
	log:        [LOG_LINES][LOG_LEN]u8,
	log_len:    [LOG_LINES]int,
	menu_text:  [MENU_MAX][MENU_TEXT]u8, // storage for menu labels built on the fly
}

// A fresh game on the title screen; the title shows the world New voyage will build.
title :: proc(g: ^Game, seed: u64) {
	best, has_best, muted := g.best, g.has_best, g.muted
	g^ = {}
	g.best, g.has_best, g.muted = best, has_best, muted
	g.next_seed = seed
	start_world(g, seed)
	logf(g, "Welcome aboard.")
}

// Builds the world for seed and puts the ship at its home port, the first island, docked.
start_world :: proc(g: ^Game, seed: u64) {
	g.seed = seed
	g.rng = rng_make(seed)
	generate_world(g)
	g.ship = {x = WORLD_SIZE / 2, y = WORLD_SIZE / 2, heading = 0, speed = 100}
	g.docked = NO_ISLAND
	g.money = START_MONEY
	g.cargo = {}
	generate_markets(g)
	generate_districts(g)
	generate_stakes(g)
	g.hand_state = .None
	for i in 0 ..< ISLAND_MAX {g.seen[i] = {turn = NEVER_SEEN}}
	g.n_offers, g.n_carried, g.deliveries_made = 0, 0, 0
	g.vendor_stock = VENDOR_STOCK
	g.rations = START_RATIONS
	g.satiety = STAT_MAX
	g.health = STAT_MAX
	g.foul = {}
	g.outcome = .None
	plain_captain(g)
	g.n_candidates, g.n_logbook, g.wage_turns, g.log_page = 0, 0, 0, 0
	if g.n_islands > 0 {
		if x, y, ok := mooring(g, 0); ok {
			g.ship.x, g.ship.y = x, y
			g.docked = 0
		}
	}
	look(g)
	make_offers(g)
	record_prices(g)
}

menu :: proc(g: ^Game) -> (m: Menu) {
	add :: proc(g: ^Game, m: ^Menu, label: string, cmd: Cmd, arg := 0) {
		assert(m.n < MENU_MAX, "menu overflow")
		m.items[m.n] = {label, cmd, arg}
		m.n += 1
	}
	addf :: proc(g: ^Game, m: ^Menu, cmd: Cmd, arg: int, format: string, args: ..any) {
		if m.n == MENU_MAX {return}
		label := fmt.bprintf(g.menu_text[m.n][:], format, ..args)
		add(g, m, label, cmd, arg)
	}
	sound_label := g.muted ? "Sound: off" : "Sound: on"

	switch g.screen {
	case .Title:
		if g.has_voyage {add(g, &m, "Continue voyage", .Continue)}
		add(g, &m, "New voyage", .New_Voyage)
		add(g, &m, sound_label, .Sound_Toggle)
	case .Over:
		add(g, &m, "New voyage", .New_Voyage)
		if logbook_pages(g) > 1 {addf(g, &m, .Log_Page, 0, "Log: page %d of %d", g.log_page % logbook_pages(g) + 1, logbook_pages(g))}
		add(g, &m, sound_label, .Sound_Toggle)
	case .Start:
		if g.sub == .Custom {
			for s in Skill {
				addf(g, &m, .Spend, int(s), "%s %d%%", SKILL_NAMES[s], BASE_SKILL[s] + g.spent[s])
			}
			addf(g, &m, .Begin, int(Profession.Custom), "Set sail (%d left)", points_left(g))
			return
		}
		add(g, &m, "Quick start", .Begin, QUICK)
		for p in Profession.Hunter ..= Profession.Warrior {add(g, &m, PROFESSION_NAMES[p], .Begin, int(p))}
		add(g, &m, "Custom", .Open, int(Sub.Custom))
		add(g, &m, "Back", .To_Title)
	case .Docked:
		if g.sub == .Careen {
			addf(g, &m, .Careen, int(Side.Port), "Port side %d%%", hull_clean(g, .Port))
			addf(g, &m, .Careen, int(Side.Starboard), "Starboard %d%%", hull_clean(g, .Starboard))
			add(g, &m, "Back", .Back)
			return
		}
		switch g.sub {
		case .Market:
			i := g.docked
			for good in Good {
				if good in g.trades[i] {
					addf(g, &m, .Pick_Good, int(good), "%s %d/%d", GOODS[good].name, your_cost(g, i, good), your_take(g, i, good))
				}
			}
			addf(g, &m, .Pick_Good, RATIONS, "Rations %d", ration_price(g, i))
			add(g, &m, "Back", .Back)
			return
		case .Trade:
			if g.trade_good == RATIONS {
				add(g, &m, "Buy 10 rations", .Buy, 1)
				add(g, &m, "Buy 100", .Buy, 10)
				add(g, &m, "Buy 500", .Buy, 50)
			} else {
				good := Good(g.trade_good)
				addf(g, &m, .Buy, 1, "Buy 1 at %d", your_cost(g, g.docked, good))
				add(g, &m, "Buy 10", .Buy, 10)
				add(g, &m, "Buy max", .Buy, ALL)
				addf(g, &m, .Sell, 1, "Sell 1 at %d", your_take(g, g.docked, good))
				add(g, &m, "Sell 10", .Sell, 10)
				add(g, &m, "Sell all", .Sell, ALL)
			}
			add(g, &m, "Back", .Back)
			return
		case .Deliveries:
			for k in 0 ..< g.n_offers {
				o := g.offers[k]
				addf(g, &m, .Pick_Offer, k, "To %s, %d", island_name(g, o.to), o.reward)
			}
			addf(g, &m, .Open, int(Sub.Carried), "Carried: %d of %d", g.n_carried, CARRY_MAX)
			add(g, &m, "Back", .Back)
			return
		case .Offer:
			add(g, &m, "Accept", .Accept)
			add(g, &m, "Back", .Back)
			return
		case .Carried:
			for k in 0 ..< g.n_carried {
				d := g.carried[k]
				addf(g, &m, .Pick_Carried, k, "%s, %d", island_name(g, d.to), pay_for(g, d))
			}
			add(g, &m, "Back", .Back)
			return
		case .Carried_Detail:
			add(g, &m, "Abandon it", .Abandon)
			add(g, &m, "Back", .Back)
			return
		case .Alley:
			stake := g.stakes[g.docked]
			if g.hand_state == .Dealt {
				for k in BET_STEPS {addf(g, &m, .Bet, k, "Bet %d", k * stake)}
				add(g, &m, "Fold", .Fold)
			} else {
				addf(g, &m, .Deal, 0, g.hand_state == .Shown ? "Deal again (ante %d)" : "Deal (ante %d)", stake)
				add(g, &m, "Back", .Back)
			}
			return
		case .Crew, .Member, .Tavern, .Candidate:
			crew_menu(g, &m)
			return
		case .Vendor:
			addf(g, &m, .Vendor_Buy, 1, "Buy %d rations at %d", VENDOR_LOT, vendor_price(g, g.docked))
			addf(g, &m, .Vendor_Buy, 5, "Buy %d", 5 * VENDOR_LOT)
			add(g, &m, "Back", .Back)
			return
		case .None, .Heading, .Adjust, .Speed, .Sail, .Head_For, .Dock, .Chart, .Careen, .Book, .Custom, .Logbook:
		}
		ds := g.districts[g.docked] if g.docked != NO_ISLAND else {}
		add(g, &m, "Cast off", .Undock)
		add(g, &m, "Market", .Open, int(Sub.Market))
		if .Delivery_Service in ds {add(g, &m, "Delivery service", .Open, int(Sub.Deliveries))}
		if .Street_Vendor in ds {add(g, &m, "Street vendor", .Open, int(Sub.Vendor))}
		if .Dark_Alley in ds {add(g, &m, "Dark alley", .Open, int(Sub.Alley))}
		if .Tavern in ds {add(g, &m, "Tavern", .Open, int(Sub.Tavern))}
		add(g, &m, "Careen", .Open, int(Sub.Careen))
		add(g, &m, "Crew", .Open, int(Sub.Crew))
		add(g, &m, "Back to title", .To_Title)
	case .Sea:
		switch g.sub {
		case .None:
			add(g, &m, "Set heading", .Open, int(Sub.Heading))
			add(g, &m, "Adjust heading", .Open, int(Sub.Adjust))
			add(g, &m, "Set speed", .Open, int(Sub.Speed))
			add(g, &m, "Sail", .Open, int(Sub.Sail))
			if any_charted(g) {add(g, &m, "Head for", .Open, int(Sub.Head_For))}
			near: [ISLAND_MAX]int
			if dockable(g, near[:]) > 0 {add(g, &m, "Dock", .Dock, NO_ISLAND)}
			add(g, &m, "Chart", .Open, int(Sub.Chart))
			add(g, &m, "Crew", .Open, int(Sub.Crew))
			add(g, &m, "Back to title", .To_Title)
		case .Heading:
			for p in 0 ..< 8 {addf(g, &m, .Set_Heading, p * 45, "%s %03d", compass(p * 45), p * 45)}
			add(g, &m, "Back", .Back)
		case .Adjust:
			for d in ([6]int{-10, -5, -1, 1, 5, 10}) {
				addf(g, &m, .Adjust, d, "%s %d", d < 0 ? "Port" : "Starboard", abs(d))
			}
			add(g, &m, "Back", .Back)
		case .Speed:
			add(g, &m, "Full sail", .Set_Speed, 100)
			add(g, &m, "Three quarters", .Set_Speed, 75)
			add(g, &m, "Half sail", .Set_Speed, 50)
			add(g, &m, "Quarter sail", .Set_Speed, 25)
			add(g, &m, "All stop", .Set_Speed, 0)
			add(g, &m, "Back", .Back)
		case .Sail:
			for t in ([5]int{1, 3, 5, 10, 25}) {addf(g, &m, .Sail, t, "%d turn%s", t, t == 1 ? "" : "s")}
			add(g, &m, "Back", .Back)
		case .Head_For:
			near: [ISLAND_MAX]int
			n := charted_by_distance(g, near[:])
			first, last := 0, n // all of them when they fit with Back
			pages := 1
			if n > MENU_MAX - 1 {
				pages = (n + HEAD_FOR_PAGE - 1) / HEAD_FOR_PAGE
				first = (g.page % pages) * HEAD_FOR_PAGE
				last = min(first + HEAD_FOR_PAGE, n)
			}
			for j in first ..< last {
				i := near[j]
				d := int(math.round(island_distance(g, i, g.ship.x, g.ship.y)))
				addf(g, &m, .Head_For, i, "%s%s %d %s", is_destination(g, i) ? "*" : "", island_name(g, i), d, compass(bearing_to(g, i)))
			}
			if pages > 1 {addf(g, &m, .Next_Page, 0, "More (page %d of %d)", g.page % pages + 1, pages)}
			add(g, &m, "Back", .Back)
		case .Dock:
			near: [MENU_MAX - 1]int
			n := dockable(g, near[:])
			for j in 0 ..< n {add(g, &m, island_name(g, near[j]), .Dock, near[j])}
			add(g, &m, "Back", .Back)
		case .Chart:
			add(g, &m, "Price book", .Open, int(Sub.Book))
			add(g, &m, "Captain's log", .Open, int(Sub.Logbook))
			add(g, &m, "Back", .Back)
		case .Logbook:
			if logbook_pages(g) > 1 {addf(g, &m, .Log_Page, 0, "Page %d of %d", g.log_page % logbook_pages(g) + 1, logbook_pages(g))}
			add(g, &m, "Back", .Back)
		case .Crew, .Member, .Tavern, .Candidate:
			crew_menu(g, &m)
		case .Book:
			add(g, &m, "Next good", .Book_Step, 1)
			add(g, &m, "Previous good", .Book_Step, -1)
			add(g, &m, "Back", .Back)
		case .Careen, .Market, .Trade, .Deliveries, .Offer, .Carried, .Carried_Detail, .Vendor, .Alley, .Custom:
			add(g, &m, "Back", .Back)
		}
	}
	return
}

// The crew, member, tavern and candidate submenus, at sea or docked.
crew_menu :: proc(g: ^Game, m: ^Menu) {
	put :: proc(g: ^Game, m: ^Menu, cmd: Cmd, arg: int, label: string) {
		assert(m.n < MENU_MAX, "menu overflow")
		m.items[m.n] = {label, cmd, arg}
		m.n += 1
	}
	nb: [NAME_LEN]u8
	#partial switch g.sub {
	case .Crew:
		for k in 0 ..< g.n_crew {
			c := g.crew[k]
			name := member_name(c, nb[:])
			label := k == 0 ? fmt.bprintf(g.menu_text[m.n][:], "Capt. %s", name) : fmt.bprintf(g.menu_text[m.n][:], "%s, %s", name, PROFESSION_NAMES[c.profession])
			put(g, m, .Pick_Member, k, label)
		}
		if g.screen == .Sea {put(g, m, .Fish, 0, fmt.bprintf(g.menu_text[m.n][:], "Fish (%d turns)", FISH_TURNS))}
	case .Member:
		if g.screen == .Docked && g.pick >= 1 && g.pick < g.n_crew {put(g, m, .Dismiss, 0, "Pay off and dismiss")}
	case .Tavern:
		for k in 0 ..< g.n_candidates {
			c := g.candidates[k]
			put(g, m, .Pick_Candidate, k, fmt.bprintf(g.menu_text[m.n][:], "%s, %s %d", member_name(c, nb[:]), PROFESSION_NAMES[c.profession], c.wage))
		}
	case .Candidate:
		if g.pick < g.n_candidates {put(g, m, .Hire, 0, fmt.bprintf(g.menu_text[m.n][:], "Hire (wage %d)", g.candidates[g.pick].wage))}
	}
	put(g, m, .Back, 0, "Back")
}

points_left :: proc(g: ^Game) -> int {
	n := SKILL_POINTS
	for s in Skill {n -= g.spent[s]}
	return n
}

any_charted :: proc(g: ^Game) -> bool {
	for i in 0 ..< g.n_islands {
		if g.islands[i].charted {return true}
	}
	return false
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
		if g.sub != .None {
			do_cmd(g, .Back, 0)
		} else if g.screen != .Title {
			do_cmd(g, .To_Title, 0)
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
	do_cmd(g, m.items[i].cmd, m.items[i].arg)
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

open :: proc(g: ^Game, s: Sub) {
	if g.sub == .Alley && s != .Alley {fold(g)} // leaving the table folds the hand
	if s == .Head_For && g.sub != .Head_For {g.page = 0}
	if s == .Logbook && g.sub != .Logbook {g.log_page = 0}
	if s == .Custom && g.sub != .Custom {g.spent = {}}
	g.sub = s
	g.cursor = 0
}

do_cmd :: proc(g: ^Game, cmd: Cmd, arg: int) {
	sound(g, .Select)
	switch cmd {
	case .New_Voyage:
		// Choose a captain first; the voyage (and the world) only starts with Begin, so backing out keeps the old one.
		g.screen = .Start
		g.sub = .None
		g.cursor = 0
		g.spent = {}
	case .Begin:
		if g.screen != .Start {return}
		if arg == QUICK {
			r := rng_make(g.next_seed ~ 0x0C_1C_C5_7A)
			p := Profession(rng_below(&r, 4))
			begin_voyage(g, p, profession_skills(p))
		} else if arg == int(Profession.Custom) {
			if g.sub != .Custom {
				open(g, .Custom)
				return
			}
			skills := BASE_SKILL
			for s in Skill {skills[s] += g.spent[s]}
			begin_voyage(g, .Custom, skills)
		} else if arg >= 0 && arg < int(Profession.Custom) {
			begin_voyage(g, Profession(arg), profession_skills(Profession(arg)))
		} else {
			return
		}
		nb: [NAME_LEN]u8
		logf(g, "%s takes command.", member_name(g.crew[0], nb[:]))
	case .Spend:
		if g.sub != .Custom || arg < 0 || arg > int(max(Skill)) {return}
		s := Skill(arg)
		if points_left(g) < SKILL_STEP || BASE_SKILL[s] + g.spent[s] + SKILL_STEP > SKILL_CAP {
			sound(g, .Deny)
			return
		}
		g.spent[s] += SKILL_STEP
	case .Pick_Member:
		if arg < 0 || arg >= g.n_crew {return}
		g.pick = arg
		open(g, .Member)
	case .Dismiss:
		if g.sub != .Member {return}
		nb: [NAME_LEN]u8
		name := member_name(g.crew[g.pick], nb[:])
		if !dismiss(g, g.pick) {
			sound(g, .Deny)
			return
		}
		logf(g, "%s goes ashore.", name)
		open(g, .Crew)
		g.want_save = true
	case .Fish:
		if g.screen != .Sea || g.sub != .Crew {return}
		n := fish(g)
		if g.screen == .Sea {
			if n > 0 {
				logf(g, "Caught %d rations.", n)
			} else {
				logf(g, "Nothing biting.")
			}
			sound(g, .Bell)
		}
		g.want_save = true
	case .Pick_Candidate:
		if g.screen != .Docked || arg < 0 || arg >= g.n_candidates {return}
		g.pick = arg
		open(g, .Candidate)
	case .Hire:
		if g.sub != .Candidate {return}
		c := g.candidates[g.pick]
		if !hire(g, g.pick) {
			sound(g, .Deny)
			logf(g, "No room: %d aboard.", CREW_MAX)
			return
		}
		nb: [NAME_LEN]u8
		logf(g, "%s signs on.", member_name(c, nb[:]))
		open(g, .Tavern)
		g.want_save = true
	case .Log_Page:
		g.log_page += 1
		g.cursor = 0
	case .Continue:
		if !g.has_voyage {return}
		g.screen = g.docked == NO_ISLAND ? .Sea : .Docked
		g.sub = .None
		g.cursor = 0
	case .Sound_Toggle:
		g.want_mute = true
	case .To_Title:
		g.screen = .Title
		g.sub = .None
		g.cursor = 0
	case .Open:
		if arg < 0 || arg > int(max(Sub)) {return}
		open(g, Sub(arg))
	case .Back:
		#partial switch g.sub {
		case .Trade: open(g, .Market)
		case .Offer, .Carried: open(g, .Deliveries)
		case .Carried_Detail: open(g, .Carried)
		case .Book, .Logbook: open(g, .Chart)
		case .Member: open(g, .Crew)
		case .Candidate: open(g, .Tavern)
		case: open(g, .None)
		}
	case .Set_Heading:
		g.ship.heading = wrap_heading(arg)
		logf(g, "Heading %03d %s.", g.ship.heading, compass(g.ship.heading))
		open(g, .None)
		g.want_save = true
	case .Adjust:
		g.ship.heading = wrap_heading(g.ship.heading + arg)
		logf(g, "Heading %03d %s.", g.ship.heading, compass(g.ship.heading))
		g.want_save = true
	case .Set_Speed:
		g.ship.speed = clamp(arg, 0, 100)
		if g.ship.speed == 0 {
			logf(g, "All stop.")
		} else {
			logf(g, "Speed %d%%.", g.ship.speed)
		}
		open(g, .None)
		g.want_save = true
	case .Sail:
		sail(g, clamp(arg, 1, 100))
		g.want_save = true
	case .Head_For:
		if arg < 0 || arg >= g.n_islands || !g.islands[arg].charted {return}
		g.ship.heading = bearing_to(g, arg)
		logf(g, "For %s, %03d.", island_name(g, arg), g.ship.heading)
		open(g, .None)
		g.want_save = true
	case .Dock:
		near: [ISLAND_MAX]int
		n := dockable(g, near[:])
		target := NO_ISLAND
		if arg == NO_ISLAND {
			if n == 1 {
				target = near[0]
			} else if n > 1 {
				open(g, .Dock)
				return
			}
		} else {
			for j in 0 ..< n {if near[j] == arg {target = arg}}
		}
		if target == NO_ISLAND {
			sound(g, .Deny)
			logf(g, "Nothing to dock at.")
			return
		}
		g.docked = target
		g.screen = .Docked
		open(g, .None)
		sound(g, .Dock)
		logf(g, "Docked at %s.", island_name(g, target))
		if g.seen[target].turn == NEVER_SEEN {note(g, .Landfall, target, 0)}
		if done, paid := complete_deliveries(g); done > 0 {
			sound(g, .Coins)
			logf(g, "Delivered %d: paid %d.", done, paid)
			note(g, .Delivered, target, paid)
		}
		if w := settle_crew(g); w > 0 {logf(g, "Wages paid: %d.", w)}
		make_offers(g)
		make_candidates(g)
		record_prices(g)
		g.vendor_stock = VENDOR_STOCK
		g.want_save = true
	case .Careen:
		if arg < 0 || arg > int(max(Side)) {return}
		careen(g, Side(arg))
		if g.screen != .Over {open(g, .None)}
		g.want_save = true
	case .Pick_Good:
		if g.docked == NO_ISLAND {return}
		if arg != RATIONS && (arg < 0 || arg > int(max(Good)) || Good(arg) not_in g.trades[g.docked]) {return}
		g.trade_good = arg
		open(g, .Trade)
	case .Buy:
		if g.docked == NO_ISLAND || g.sub != .Trade {return}
		n, cost: int
		if g.trade_good == RATIONS {
			n, cost = buy_rations(g, arg)
			n *= RATION_LOT
		} else {
			n, cost = buy(g, Good(g.trade_good), arg)
		}
		if n > 0 {
			sound(g, .Coins)
			logf(g, "Bought %d for %d.", n, cost)
			record_prices(g)
			g.want_save = true
		} else {
			sound(g, .Deny)
			full := g.trade_good != RATIONS && hold_used(g) + GOODS[Good(g.trade_good)].tons > HOLD_TONS
			logf(g, full ? "The hold is full." : "Not enough money.")
		}
	case .Sell:
		if g.docked == NO_ISLAND || g.sub != .Trade || g.trade_good == RATIONS {return}
		n, takings := sell(g, Good(g.trade_good), arg)
		if n > 0 {
			sound(g, .Coins)
			logf(g, "Sold %d for %d.", n, takings)
			if takings >= BIG_SALE {note(g, .Sold, g.docked, takings)}
			record_prices(g)
			g.want_save = true
		} else {
			sound(g, .Deny)
			logf(g, "None aboard to sell.")
		}
	case .Pick_Offer:
		if g.screen != .Docked || arg < 0 || arg >= g.n_offers {return}
		g.pick = arg
		open(g, .Offer)
	case .Accept:
		if g.sub != .Offer {return}
		if !accept_offer(g, g.pick) {
			sound(g, .Deny)
			logf(g, "You carry %d already.", CARRY_MAX)
			return
		}
		d := g.carried[g.n_carried - 1]
		logf(g, "For %s by turn %d.", island_name(g, d.to), d.due)
		open(g, .Deliveries)
		g.want_save = true
	case .Pick_Carried:
		if arg < 0 || arg >= g.n_carried {return}
		g.pick = arg
		open(g, .Carried_Detail)
	case .Abandon:
		if g.sub != .Carried_Detail || !abandon(g, g.pick) {return}
		logf(g, "Delivery abandoned.")
		open(g, .Carried)
		g.want_save = true
	case .Vendor_Buy:
		if g.sub != .Vendor {return}
		n, cost := buy_from_vendor(g, arg)
		if n > 0 {
			sound(g, .Coins)
			logf(g, "Bought %d for %d.", n * VENDOR_LOT, cost)
			g.want_save = true
		} else {
			sound(g, .Deny)
			logf(g, g.vendor_stock == 0 ? "Sold out today." : "Not enough money.")
		}
	case .Next_Page:
		g.page += 1
		g.cursor = 0
	case .Deal:
		if g.sub != .Alley || g.hand_state == .Dealt {return}
		if !deal(g) {
			sound(g, .Deny)
			logf(g, "The ante is %d.", g.stakes[g.docked])
			return
		}
		sound(g, .Deal)
		g.cursor = 0
		if is_pair(g.hand[0], g.hand[1]) {logf(g, "A pair: any bet loses.")}
		g.want_save = true
	case .Bet:
		if g.sub != .Alley || g.hand_state != .Dealt {return}
		if !place_bet(g, arg) {
			sound(g, .Deny)
			logf(g, "You can't cover that.")
			return
		}
		sound(g, g.hand_won ? .Win : .Bust)
		if g.palmed {logf(g, "A card is swapped...")}
		logf(g, g.hand_won ? "Between! Won %d." : "Not between: lost %d.", g.bet)
		if g.hand_won && g.bet >= BIG_WIN {note(g, .Won, g.docked, g.bet)}
		g.cursor = 0
		g.want_save = true
	case .Fold:
		if g.hand_state != .Dealt {return}
		fold(g)
		logf(g, "Folded.")
		g.cursor = 0
	case .Book_Step:
		g.book_good = Good((int(g.book_good) + len(Good) + (arg < 0 ? -1 : 1)) % len(Good))
	case .Undock:
		if g.docked != NO_ISLAND {logf(g, "Cast off from %s.", island_name(g, g.docked))}
		g.docked = NO_ISLAND
		g.n_offers = 0 // offers stay at the island
		g.n_candidates = 0 // and so do the sailors at the tavern
		g.screen = .Sea
		open(g, .None)
		g.want_save = true
	}
}

// Sail up to turns turns along the heading at the current speed. Stops early at land, at the edge of the charts, or
// on sighting a new island. At all stop the turns simply pass.
sail :: proc(g: ^Game, turns: int) {
	rad := f32(g.ship.heading) * math.PI / 180
	for t in 0 ..< turns {
		if g.screen != .Sea {return}
		step := effective_speed(g) / 100
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
		if !tick(g, g.ship.speed > 0) {return}
		if s := look(g); s != NO_ISLAND {
			sound(g, .Sighted)
			logf(g, "Sighted %s!", island_name(g, s))
			return
		}
		if t == turns - 1 {
			if g.ship.speed == 0 {
				logf(g, "Waited %d turn%s.", turns, turns == 1 ? "" : "s")
			} else {
				logf(g, "Sailed %d turn%s %s.", turns, turns == 1 ? "" : "s", compass(g.ship.heading))
			}
			sound(g, .Bell)
		}
	}
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
