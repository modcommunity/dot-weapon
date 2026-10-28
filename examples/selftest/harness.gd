extends Node

## dot-weapon's self-test. Headless, no network, no scene but this one.
## Printed at the end: sections entered against sections that ran to their last line, and a total of checks;
## a script error aborts its section after it announced itself, so the entered count alone proves nothing.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sections_entered: int = 0
var _sections_finished: int = 0

const RATE := 64


func _section(name: String) -> void:
	_sections_entered += 1
	print("")
	print("-- %s" % name)


func _done() -> void:
	_sections_finished += 1


func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("   ok   %s" % what)
	else:
		_failed += 1
		_failures.append("%s%s" % [what, "  (%s)" % detail if detail != "" else ""])
		print("  FAIL  %s%s" % [what, "  (%s)" % detail if detail != "" else ""])
	return condition


func _close(got: float, want: float, what: String, epsilon: float = 0.01) -> bool:
	return _check(absf(got - want) <= epsilon, what, "got %.4f, want %.4f" % [got, want])


func _catalogue_extra() -> DotWeaponDef:
	var d := _pistol()
	d.id = &"toy_blaster"
	return d


const _HITSCAN := "res://addons/dot_weapon/behaviour/dot_weapon_hitscan.gd"
const _PROJECTILE := "res://addons/dot_weapon/behaviour/dot_weapon_projectile.gd"
const _MELEE := "res://addons/dot_weapon/behaviour/dot_weapon_melee.gd"
const _BEAM := "res://addons/dot_weapon/behaviour/dot_weapon_beam.gd"
const _THROWN := "res://addons/dot_weapon/behaviour/dot_weapon_thrown.gd"
const _ROD := "res://fixtures/lightning_rod.gd"


func _ballistics(damage: float) -> DotWeaponBallistics:
	var b := DotWeaponBallistics.new()
	b.damage = damage
	b.spread = 0.0
	b.spread_moving = 0.0
	b.spread_airborne = 0.0
	b.bloom = 0.0
	b.recoil_pitch = 0.5
	b.recoil_yaw = 0.2
	return b


func _rifle() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"rifle"
	d.display_name = "Rifle"
	d.behaviour_path = _HITSCAN
	d.slot = 1
	d.fire_mode = DotWeaponDef.Fire.AUTO
	d.use_interval_ticks = 6
	d.magazine = 30
	d.reserve = 90
	d.ammo_type = &"rifle_rounds"
	d.reload_ticks = 120
	d.deploy_ticks = 0
	d.holster_ticks = 0
	d.tuning = _ballistics(25.0)
	d.tags = [&"primary"] as Array[StringName]
	return d


func _pistol() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"pistol"
	d.behaviour_path = _HITSCAN
	d.slot = 2
	d.fire_mode = DotWeaponDef.Fire.SEMI
	d.use_interval_ticks = 8
	d.magazine = 12
	d.reserve = 36
	d.ammo_type = &"pistol_rounds"
	d.reload_ticks = 90
	d.deploy_ticks = 0
	d.holster_ticks = 0
	d.tuning = _ballistics(30.0)
	return d


func _bow() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"bow"
	d.behaviour_path = _PROJECTILE
	d.slot = 3
	d.fire_mode = DotWeaponDef.Fire.CHARGE
	d.charge_ticks = 64
	d.use_interval_ticks = 8
	d.ammo_type = &"arrows"
	d.reserve = 20
	d.magazine = 0
	d.deploy_ticks = 0
	d.holster_ticks = 0

	var b := _ballistics(70.0)
	b.min_charge_damage = 0.2
	b.speed = 90.0
	b.min_speed = 25.0
	b.gravity_scale = 1.0
	d.tuning = b
	return d


func _knife() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"knife"
	d.behaviour_path = _MELEE
	d.slot = 4
	d.fire_mode = DotWeaponDef.Fire.SEMI
	d.use_interval_ticks = 20
	d.deploy_ticks = 0
	d.holster_ticks = 0

	var b := _ballistics(55.0)
	b.max_range = 2.0
	d.tuning = b
	d.params = {&"arc_degrees": 40.0, &"rays": 5}
	return d


func _flamer() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"flamer"
	d.behaviour_path = _BEAM
	d.slot = 5
	d.fire_mode = DotWeaponDef.Fire.HOLD
	d.use_interval_ticks = 4
	d.ammo_type = &"fuel"
	d.reserve = 200
	d.magazine = 0
	d.deploy_ticks = 0
	d.holster_ticks = 0

	var b := _ballistics(6.0)
	b.max_range = 12.0
	d.tuning = b
	d.params = {&"ramp_ticks": 16, &"ramp_from": 0.5}
	return d


func _grenade() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"grenade"
	d.behaviour_path = _THROWN
	d.slot = 6
	d.fire_mode = DotWeaponDef.Fire.CHARGE
	d.charge_ticks = 192
	d.use_interval_ticks = 30
	d.ammo_type = &"grenades"
	d.reserve = 2
	d.magazine = 0
	d.deploy_ticks = 0
	d.holster_ticks = 0

	var b := _ballistics(0.0)
	b.speed = 18.0
	b.min_speed = 18.0
	b.splash_radius = 5.0
	b.splash_damage = 110.0
	d.tuning = b
	d.params = {&"fuse_ticks": 192}
	return d


func _rod() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"rod"
	d.behaviour_path = _ROD
	d.slot = 7
	d.fire_mode = DotWeaponDef.Fire.SEMI
	d.use_interval_ticks = 5
	d.ammo_type = &"charges"
	d.reserve = 9
	d.magazine = 0
	d.deploy_ticks = 0
	d.holster_ticks = 0
	d.params = {&"damage": 18.0, &"max_chain": 3, &"charges": 3, &"max_range": 40.0}
	return d


func _catalogue() -> DotWeaponCatalogue:
	var c := DotWeaponCatalogue.new()
	c.add(_rifle()).add(_pistol()).add(_bow()).add(_knife())
	c.add(_flamer()).add(_grenade()).add(_rod())
	return c


func _arsenal(catalogue: DotWeaponCatalogue = null) -> DotWeaponArsenal:
	var a := DotWeaponArsenal.new()
	a.catalogue = catalogue if catalogue != null else _catalogue()
	a.tick_rate = RATE
	a.authority = true
	add_child(a)
	var res := a.setup()
	if not res.ok:
		push_error(res.error.message)
	return a


func _ctx(tick: int, entity: int = 1) -> DotWeaponContext:
	return DotWeaponContext.make(entity, tick, Vector3(0.0, 1.6, 0.0), Vector3.FORWARD)


func _cmd(attack: bool = false, slot: int = 0) -> DotWeaponCommand:
	var c := DotWeaponCommand.new()
	c.set_button(DotWeaponCommand.BUTTON_ATTACK, attack)
	c.slot = slot
	return c


## Runs an arsenal for a span of ticks, holding the given buttons, collecting outcomes.
func _drive(
	arsenal: DotWeaponArsenal,
	from_tick: int,
	ticks: int,
	attack: bool,
	entity: int = 1
) -> Array[DotWeaponOutcome]:
	var out: Array[DotWeaponOutcome] = []
	var previous: DotWeaponCommand = null

	for i in range(ticks):
		var cmd := _cmd(attack)
		var result := arsenal.simulate_tick(cmd, _ctx(from_tick + i, entity), previous)
		if result.used:
			out.append(result)
		previous = cmd

	return out


func _drop(node: Node) -> void:
	remove_child(node)
	node.queue_free()
