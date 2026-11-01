extends RefCounted
## Council voting. An accusation only happens with a strict majority of
## eligible voters. Ties or a split vote mean nobody is accused that day.

const ABSTAIN := -1
const NO_ACCUSATION := -1

## voter_id -> target_id (or ABSTAIN)
var votes := {}


func reset() -> void:
	votes.clear()


func cast(voter_id: int, target_id: int) -> void:
	votes[voter_id] = target_id


func has_voted(voter_id: int) -> bool:
	return votes.has(voter_id)


## eligible_voters: how many players could vote. Abstaining or not voting
## still counts against the majority.
func tally(eligible_voters: int) -> Dictionary:
	var counts := {}
	for target in votes.values():
		if target == ABSTAIN:
			continue
		counts[target] = counts.get(target, 0) + 1

	var top_target := NO_ACCUSATION
	var top_count := 0
	var tied := false
	for target in counts.keys():
		var c: int = counts[target]
		if c > top_count:
			top_target = target
			top_count = c
			tied = false
		elif c == top_count:
			tied = true

	var majority := not tied and top_count * 2 > eligible_voters
	return {
		"accused": top_target if majority else NO_ACCUSATION,
		"counts": counts,
		"top_count": top_count,
		"majority": majority,
	}
