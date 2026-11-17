class_name DotWeaponKnifeCvars
extends RefCounted
## The rules of [DotWeaponKnives] as cvars: which suffix sets which rule, and the binding.

const SPECS := {
	"_throw": ["enabled", "The aim key throws a knife in hand (1), or does nothing (0)"],
	"_throw_speed": ["speed", "Metres per second a thrown knife leaves the hand at"],
	"_throw_pickup": ["pickup", "Metres from a lying or embedded knife a player picks it up (0 off)"],
	"_throw_damage": ["damage", "Damage a thrown knife deals to the first body it meets (a kill leaves it in the body)"],
	"_throw_charge": ["charge", "Holding the aim key winds the throw up and releasing throws it (1), or the press throws at once (0)"],
	"_throw_charge_sec": ["charge_sec", "Seconds of holding to reach full throw power (0 full at once)"],
	"_throw_charge_min": ["charge_min", "Fraction of the throw speed a throw released at once leaves with"],
	"_boomerang_distance": ["boomerang_distance", "Metres a Boomerang knife flies straight out before it turns back (0 flies straight on, no return)"],
	"_boomerang_radius": ["boomerang_radius", "Radius in metres of the turn a Boomerang knife circles back through (0 turns on the spot)"],
	"_boomerang_speed": ["boomerang_speed", "Metres per second a Boomerang knife flies at (0 uses the throw speed)"],
	"_boomerang_to_thrower": ["boomerang_to_thrower", "A Boomerang knife homes back to the thrower's hand (1), or to where it was thrown from (0)"],
	"_boomerang_left": ["boomerang_left", "A Boomerang knife curves left (1) or right (0)"],
	"_boomerang_catch": ["boomerang_catch", "Metres from the thrower's hand a returning Boomerang knife is caught in the air (0 never: it falls at the throw point)"],
	"_boomerang_empty_hand": ["boomerang_empty_hand", "A Boomerang thrower waits bare-handed for the catch (1), or draws the next weapon at once (0); a knife that falls or sticks instead brings the next weapon up"],
}


## Registers the rules as cvars named [param prefix] + [constant CVAR_SPECS] through [param add] (a
## server module's add_cvar, shaped [code](name, default, description, flags) -> cvar[/code]); each
## change lands in [param rules_dict]. Returns the cvars.
static func bind(rules_dict: Dictionary, add: Callable, prefix: String, flags: int = 0) -> Array:
	var made: Array = []
	for suffix: String in SPECS:
		var key: String = SPECS[suffix][0]
		var value: Variant = rules_dict[key]
		var cv: Variant = add.call(prefix + suffix, ("1" if value else "0") if value is bool else str(value), SPECS[suffix][1], flags)
		if not (cv is Object) or cv == null:
			continue
		var o := cv as Object
		if o.has_method(&"with_min"):
			var _min: Variant = o.call(&"with_min", 0.0)
		if o.has_signal(&"changed"):
			o.connect(&"changed", func(_old: String, new_value: String) -> void:
				rules_dict[key] = new_value.to_float() != 0.0 if rules_dict[key] is bool else new_value.to_float())
		made.append(o)
	return made
