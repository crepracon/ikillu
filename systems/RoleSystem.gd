extends RefCounted
## Assigns secret roles. Classes are chosen separately in the lobby, so any
## class can end up in either faction.

const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")


## Sets PlayerState.role on each player and returns the cultist ids.
## Uses the session RNG so the same seed always gives the same roles.
static func assign_roles(players: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ids: Array = players.keys()
	ids.sort() # Dictionary order isn't guaranteed; sort before shuffling.
	_shuffle(ids, rng)

	var cult_count := Config.cultist_count_for(ids.size())
	var cultists := ids.slice(0, cult_count)
	for pid in ids:
		players[pid].role = Enums.Role.CULTIST if pid in cultists else Enums.Role.VILLAGER
	return cultists


## Fisher-Yates using the session RNG (Array.shuffle() uses the global RNG).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
