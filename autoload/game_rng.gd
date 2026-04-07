extends Node
## Deterministic RNG for gameplay simulation.
## All peers share the same seed → same sequence → identical simulation.
## Use GameRNG.randf_range() etc. instead of global randf_range() for any
## call that affects game state (positions, AI decisions, spawns).
## Visual-only randomness (particles, UI) can still use global randf.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0


func set_seed(s: int) -> void:
	_rng.seed = s if s >= 0 else int(Time.get_ticks_msec())


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi() -> int:
	return _rng.randi()


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)
