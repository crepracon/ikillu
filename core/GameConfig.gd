extends RefCounted
## Rule values shared by every game mode.
## Mode-specific numbers (plot target, etc.) live on the GameMode.
## Lines marked DEFAULT are prototype guesses waiting on playtesting.

const MIN_PLAYERS := 4
const MAX_PLAYERS := 10
## Minimum players when running from the editor or a debug build, so you can
## test with 2-3 windows. Exported release builds use MIN_PLAYERS.
const TEST_MIN_PLAYERS := 2

const ACTION_POINTS_PER_DAY := 3
## A player never drops below this many action points, even when sabotaged.
const MIN_ACTION_POINTS := 1

## How many days a night sabotage lasts.
const SABOTAGE_DURATION_DAYS := 1
## Action points removed by the WEARY effect.
const WEARY_AP_PENALTY := 1


## Number of traitors for a given player count. DEFAULT
static func traitor_count_for(player_count: int) -> int:
	if player_count >= 10:
		return 3
	if player_count >= 7:
		return 2
	return 1
