extends "res://addons/dot_weapon/behaviour/dot_weapon_behaviour.gd"

## A weapon this addon knows nothing about, written the way a game would write one.
##
## [b]It exists to prove the extension point.[/b] It is not a gun, a bow, a melee
## weapon, a beam or a thrown charge; it chains to several targets at once, it costs
## more ammunition the more it chains, it refuses to fire indoors, and it keeps its own
## cooldown. None of those ideas appear anywhere in dot-weapon, and adding it required
## editing no file in the addon: it extends the base **by path**, reads its tuning from
## [member DotWeaponDef.params], and returns an ordinary [DotWeaponOutcome].
##
## The suite asserts all of that, because "it is extensible" is the kind of claim that
## is true when it is written and false four refactors later.

const _CHARGES := &"charges"


func _setup() -> void:
	state[_CHARGES] = tune_int(&"charges", 3)


func _can_use(ctx: DotWeaponContext) -> DotResult:
	# A rule the addon has no concept of: this weapon needs open sky.
	if bool(ctx.extra.get("indoors", false)):
		return DotResult.fail(DotError.CODE_STATE, "The sky is not visible here.")

	if int(state.get(_CHARGES, 0)) <= 0:
		return DotResult.fail(DotError.CODE_STATE, "No charges left.")

	return DotResult.success(null)


func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var targets: Array = ctx.extra.get("targets", [])
	var chain := mini(targets.size(), tune_int(&"max_chain", 3))

	var out := DotWeaponOutcome.of(&"chain_lightning")

	for i in range(chain):
		var shot := DotShot.make(def.id, ctx.entity, ctx.tick, ctx.index + i)
		shot.origin = ctx.origin
		shot.direction = ctx.direction
		shot.damage = tune_float(&"damage", 18.0) / float(i + 1)
		shot.max_range = tune_float(&"max_range", 40.0)
		shot.pellet_count = 1
		shot.scatter()
		out.add_shot(shot)

	# Costs one charge per link, which is a cost rule no field on a definition has.
	out.ammo_used = maxi(1, chain)
	# And sets its own cadence from how far it chained.
	out.cooldown_ticks = 10 + chain * 5

	state[_CHARGES] = int(state.get(_CHARGES, 0)) - 1
	out.add_event({"event": "chained", "links": chain})

	return out


func charges_left() -> int:
	return int(state.get(_CHARGES, 0))
