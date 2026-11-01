extends RefCounted
## Tunable rule values in one place.
## Lines marked DEFAULT are prototype guesses waiting on playtesting.

const MIN_PLAYERS := 4
const MAX_PLAYERS := 10

const ACTION_POINTS_PER_DAY := 3
## A player never drops below this many action points, even when hexed.
const MIN_ACTION_POINTS := 1

## The cult wins when the ritual reaches this value.
const RITUAL_TARGET := 5 # DEFAULT
## Ritual gained when the cult chooses to advance it at night.
const RITUAL_PER_ADVANCE := 1 # DEFAULT
## Ritual gained when the village accuses an innocent player at council.
const WRONG_ACCUSATION_RITUAL_BONUS := 1 # DEFAULT
## Whether everyone can see ritual progress. Visible progress creates urgency.
const RITUAL_PROGRESS_PUBLIC := true # DEFAULT

## How many days a night hex lasts.
const HEX_DURATION_DAYS := 1
## Action points removed by the WEARY effect.
const WEARY_AP_PENALTY := 1


## Number of cultists for a given player count. DEFAULT
static func cultist_count_for(player_count: int) -> int:
	if player_count >= 10:
		return 3
	if player_count >= 7:
		return 2
	return 1
