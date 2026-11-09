extends RefCounted

## The scope-view rules a view model shares with every other: lens or full screen, the camera's
## field of view, the walking clear. Preloaded by path, no `class_name`. A view model keeps its
## `scope_mode`, `scope_walk_clear` and `scope_walk_speed` fields (a game sets them) and calls these.

## The scope as a lens on a normal screen, and the scope filling it.
const LENS := 1
const FULL := 2


## The view the player [param wanted] (clamped to LENS or FULL), or [param forced] when the server's rule pins one (above 0).
static func resolve(wanted: int, forced: int = 0) -> int:
	return forced if forced > 0 else clampi(wanted, LENS, FULL)


## Whether the scope is a lens: the camera stays at the hip's field of view and the overlay's own camera zooms.
static func is_lens(mode: int, has_scope: bool) -> bool:
	return mode == LENS and has_scope


## The multiplier the main camera takes: 1 with the scope as a lens, else [param aim_scale].
static func fov_scale(lens: bool, aim_scale: float) -> float:
	return 1.0 if lens else aim_scale


## How much of the scope's picture is clear because the player moves: 0 standing, [param walk_clear] at [param walk_speed] m/s.
static func clear(has_scope: bool, walk_clear: float, walk_speed: float, speed: float) -> float:
	if not has_scope or walk_speed <= 0.0:
		return 0.0
	return walk_clear * smoothstep(0.3, walk_speed, speed)
