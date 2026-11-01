extends RefCounted
## Sliding-window rate limiter keyed by peer id.

var _max_count: int
var _window_ms: int
## peer_id -> Array of send times (ms)
var _times := {}


func _init(max_count: int, window_ms: int) -> void:
	_max_count = max_count
	_window_ms = window_ms


## Returns true and records the send if the peer is under the limit.
func allow(peer_id: int, now_ms: int) -> bool:
	var recent := []
	for t in _times.get(peer_id, []):
		if now_ms - t < _window_ms:
			recent.append(t)
	if recent.size() >= _max_count:
		_times[peer_id] = recent
		return false
	recent.append(now_ms)
	_times[peer_id] = recent
	return true


func forget(peer_id: int) -> void:
	_times.erase(peer_id)
