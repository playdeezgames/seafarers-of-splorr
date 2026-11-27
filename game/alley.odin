package game

// The dark alley (Phase 5): Classic's in-between game with a 78-card tarot deck. Trumps (the Major Arcana) beat every
// suit card and rank among themselves by number; suit cards rank Ace low to King high, suits equal. Two cards are
// dealt face up; win even money if the third falls strictly between them. Ties lose, as in Classic: an equal pair up,
// or a third card equal to either (the user kept that rule and asked that it be shown, November 27, 2026).
//
// Classic let you fold for nothing, which made the alley a money farm (betting only on wide spreads wins about 7.5% of
// the stake per hand dealt). The user chose an ante instead: dealing costs the island's minimum stake, lost if you
// fold, and bets run from one to ten times the minimum. Leaving the alley mid-hand folds it.

DECK_SIZE :: 78
MINORS :: 56
BET_STEPS := [4]int{1, 2, 5, 10}

Hand_State :: enum u8 {
	None, // nothing dealt
	Dealt, // two cards up, ante paid, waiting for a bet or a fold
	Shown, // the third card is turned: g.hand_won says how it went
}

SUITS := [4]string{"Wands", "Cups", "Swords", "Pentacles"}
RANKS := [14]string{"Ace", "Deuce", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Page", "Knight", "Queen", "King"}
TRUMPS := [22]string {
	"The Fool", "The Magician", "The High Priestess", "The Empress", "The Emperor", "The Hierophant", "The Lovers",
	"The Chariot", "Strength", "The Hermit", "Wheel of Fortune", "Justice", "The Hanged Man", "Death", "Temperance",
	"The Devil", "The Tower", "The Star", "The Moon", "The Sun", "Judgement", "The World",
}
NUMERALS := [22]string{"0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI"}
SHORT_RANKS := [14]string{"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "P", "Kn", "Q", "K"}

// Cards 0 ..< 56 are suit cards (suit = card / 14, rank = card % 14); 56 ..< 78 are the trumps in order.
card_value :: proc(card: int) -> int {
	return card < MINORS ? card % 14 + 1 : 15 + (card - MINORS)
}

is_trump :: proc(card: int) -> bool {return card >= MINORS}

card_suit :: proc(card: int) -> int {return card / 14}

// Classic's IsWinner: strictly between, so any tie loses.
in_between :: proc(a, b, c: int) -> bool {
	lo, hi := min(card_value(a), card_value(b)), max(card_value(a), card_value(b))
	v := card_value(c)
	return lo < v && v < hi
}

is_pair :: proc(a, b: int) -> bool {return card_value(a) == card_value(b)}

// The island's minimum stake: 5 to 25, from the seed.
generate_stakes :: proc(g: ^Game) {
	r := rng_make(g.seed ~ 0xA1_1E_7C_A2_D5)
	for i in 0 ..< g.n_islands {g.stakes[i] = 5 * (1 + rng_below(&r, 5))}
}

// Pay the ante and deal three distinct cards; two are shown. False if the ante is beyond the purse.
deal :: proc(g: ^Game) -> bool {
	i := g.docked
	if i == NO_ISLAND || .Dark_Alley not_in g.districts[i] || g.money < g.stakes[i] {return false}
	g.money -= g.stakes[i]
	g.hand[0] = rng_below(&g.rng, DECK_SIZE)
	for {
		g.hand[1] = rng_below(&g.rng, DECK_SIZE)
		if g.hand[1] != g.hand[0] {break}
	}
	for {
		g.hand[2] = rng_below(&g.rng, DECK_SIZE)
		if g.hand[2] != g.hand[0] && g.hand[2] != g.hand[1] {break}
	}
	g.hand_state = .Dealt
	g.bet = 0
	return true
}

// Bet `times` the minimum on the hand: even money if the third card falls between. False if it cannot be placed.
place_bet :: proc(g: ^Game, times: int) -> bool {
	i := g.docked
	if g.hand_state != .Dealt || i == NO_ISLAND {return false}
	amount := times * g.stakes[i]
	if times < 1 || times > BET_STEPS[len(BET_STEPS) - 1] || amount > g.money {return false}
	g.bet = amount
	g.hand_won = in_between(g.hand[0], g.hand[1], g.hand[2])
	g.money = g.hand_won ? min(g.money + amount, MONEY_MAX) : g.money - amount
	g.hand_state = .Shown
	return true
}

fold :: proc(g: ^Game) {
	if g.hand_state == .Dealt {g.hand_state = .None}
}

card_name :: proc(card: int, buf: []u8) -> string {
	if is_trump(card) {return TRUMPS[card - MINORS]}
	return bprint(buf, RANKS[card % 14], " of ", SUITS[card_suit(card)])
}
