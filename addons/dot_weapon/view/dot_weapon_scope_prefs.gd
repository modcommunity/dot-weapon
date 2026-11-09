extends RefCounted

## The player's scope settings and the two client cvars that write them, shared by every game that
## draws [code]dot_weapon_scope_overlay.gd[/code]. Preloaded by path, no `class_name`; a game
## may subclass it (arena's `ArenaScopePrefs`) so its own code keeps a name. The settings are
## static: one player per client.

## cl_scope_mode: 1 shows the scope as a lens on a normal screen, 2 fills the screen with it; a server's `scope_mode` ADS rule overrides.
static var mode := 1
## cl_scope_walk_clear: how much of the scope's picture goes clear while moving (0 solid, 1 fully see-through).
static var walk_clear := 0.55


## Gives [param model] (a view model with `resolve_scope_mode`, `scope_mode` and `scope_walk_clear`) this machine's scope view and walking clear.
static func apply(model: Object) -> void:
	model.set(&"scope_walk_clear", walk_clear)
	model.set(&"scope_mode", model.call(&"resolve_scope_mode", mode))


## Registers `cl_scope_mode` and `cl_scope_walk_clear` on [param local] (a DotConsoleLocal).
static func bind_cvars(local: Object) -> void:
	local.call(&"add_var", &"cl_scope_mode", "Sniper scope view: 1 a lens in the middle of a normal screen, 2 the scope filling the screen (a server's ads scope_mode can pin one).",
		func() -> Variant: return mode,
		func(v: Variant) -> Variant:
			mode = clampi(str(v).to_int(), 1, 2)
			return DotResult.success(mode)
	)
	local.call(&"add_var", &"cl_scope_walk_clear", "How much of the scope's picture goes see-through while moving (0 solid, 1 fully clear).",
		func() -> Variant: return walk_clear,
		func(v: Variant) -> Variant:
			walk_clear = clampf(str(v).to_float(), 0.0, 1.0)
			return DotResult.success(walk_clear)
	)
