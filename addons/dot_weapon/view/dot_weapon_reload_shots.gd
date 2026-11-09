extends RefCounted
## What a first-person reload review needs that no view model owns (by path, no `class_name`): the fractions to stop at, waiting for a rig to reach one, and the contact sheet. Arena and ZZ each drive their own view model and share this.


## [param count] fractions spread over a reload, none at the very start or end (a frame at 0 or 1 is the idle pose).
static func fractions(count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in maxi(count, 0):
		out.append(float(i + 1) / float(count + 1))
	return out


## Waits (a frame at a time) until [param fraction_of] reports at least [param target], or the reload is over.
## [param fraction_of] returns the reload's progress, or a negative number when nothing is reloading.
## True when the target was reached while still reloading; false when the reload ended first or [param max_frames] ran out.
static func wait_for(tree: SceneTree, fraction_of: Callable, target: float, max_frames: int = 2000) -> bool:
	for _i in max_frames:
		var f := float(fraction_of.call())
		if f < 0.0:
			return false
		if f >= target:
			return true
		await tree.process_frame
	return false


## [param tiles] scaled to [param tile_size] and laid out [param cols] across, row after row; empty when there are none.
static func sheet(tiles: Array[Image], cols: int = 4, tile_size: Vector2i = Vector2i(480, 270)) -> Image:
	if tiles.is_empty():
		return null
	var c := clampi(cols, 1, tiles.size())
	var rows := (tiles.size() + c - 1) / c
	var out := Image.create(tile_size.x * c, tile_size.y * rows, false, Image.FORMAT_RGB8)
	for n in tiles.size():
		var tile: Image = tiles[n].duplicate()
		tile.convert(Image.FORMAT_RGB8)
		tile.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(tile, Rect2i(Vector2i.ZERO, tile_size), Vector2i((n % c) * tile_size.x, (n / c) * tile_size.y))
	return out
