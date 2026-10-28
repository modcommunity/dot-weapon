@tool
extends Node

## State, signals and read-only queries for [DotWeaponArsenal]; kept apart so the state machine stays small.

## A use produced an outcome. Carries the whole outcome so a listener can tell a swing
## from a shot without inspecting it.
signal used(outcome: DotWeaponOutcome)

## A use was attempted with nothing to spend.
signal dry_used(slot: int)

signal reload_started(slot: int)
signal reload_finished(slot: int, rounds: int)

## A charged weapon reached full draw. For a sound and a HUD tick, nothing else.
signal charge_full(slot: int)

signal switched(from: int, to: int)

## The held gun's fire mode changed; [param mode] is a [enum DotWeaponDef.Fire].
signal fire_mode_changed(slot: int, mode: int)
signal ammo_changed(pool: StringName, amount: int)
signal carried_changed()

const _Io := preload("dot_weapon_arsenal_io.gd")

@export_group("Simulation")

## Ticks per second the simulation runs at, as the caller declares it.
##
## [b]A definition that names its [member DotWeaponDef.authored_tick_rate] is scaled to
## this[/b], through [method ticks_for]: a pack written at 64 Hz deploys, fires, reloads
## and charges in the same wall-clock time at 128. A definition that names none (zero) is
## used exactly as written, whatever this says, which is every definition written before
## the field existed.
##
## [b]Set it to the same number on the client and the server.[/b] Every deadline below is
## an absolute tick computed from this, and it travels in [method snapshot] as a tick, not
## as a duration; two ends at two rates predict two different reload ends. A game sets it
## from the rate its world runs at, which both ends already agree on.
@export_range(1, 240, 1) var tick_rate: int = 64

@export_range(1, 16, 1) var max_slots: int = 8

@export_group("Content")

## Every weapon this carrier could hold. Required before [method setup].
@export var catalogue: DotWeaponCatalogue = null

## The attachment catalogue. Null means nothing can be fitted. Plain var: it is a RefCounted.
## Must be the same on every machine (see [DotWeaponAttachments]).
var attachments: DotWeaponAttachments = null

## Weight and slot-capacity rules, shared by every arsenal of a game. Null: no limit, one weapon per slot.
var carry: DotWeaponCarry = null

## Backpack tier this carrier wears (0: none); see [method DotWeaponCarry.limit_for].
var backpack_tier: int = 0

## Movement-dependent spread (`sv_spread_*`); null or disabled leaves every gun's own spread.
var spread_rules: DotWeaponSpreadRules = null

## Per-weapon recoil patterns (`sv_recoil_*`); null or disabled leaves every gun's flat kick.
var recoil_rules: DotWeaponRecoilRules = null

## Global ballistics switch (`sv_ballistics`); null or off keeps every gun hitscan. Set on both sides.
var ballistics_rules: DotWeaponBallisticsRules = null

## Loaded round per weapon id (see [DotWeaponAmmoTypes]); server side only, not in snapshots.
var loaded_ammo: Dictionary = {}

@export_group("Rules")

## Switches away from a weapon that has run out entirely.
@export var auto_switch_on_empty: bool = true

## Refuses everything. For a dead player, a cutscene, a freeze time.
@export var disabled: bool = false

## True on the machine that decides. Handed to every [DotWeaponContext].
##
## A behaviour must not apply anything when this is false, and dot-combat must not
## resolve damage. A client still runs everything, for prediction.
@export var authority: bool = false

var _slots: Dictionary = {}          ## int -> DotWeaponSlot (the one in hand of that slot)
var _shelf: Dictionary = {}          ## int -> Array[DotWeaponSlot], stowed behind the active one
var _ammo := DotWeaponAmmo.new()
var _current: int = 0
var _previous: int = 0

## Tick the current weapon may next be used on.
var _next_use_tick: int = 0

## Switching: the slot being switched to, and the tick the switch completes on.
var _switch_to: int = 0
var _switch_done_tick: int = -1
var _holstering: bool = false

## Reloading: the tick the reload (or the next round of it) completes on.
var _reload_done_tick: int = -1
var _reloading: bool = false

## Burst: uses left in the burst, and the tick the next one is due.
var _burst_left: int = 0

## Charge: the tick the use button went down on. -1 when it is not down.
var _charge_started: int = -1
var _charge_announced: bool = false

## Ticks the use button has been held, for a HOLD weapon.
var _held_ticks: int = 0

## Uses so far, so two uses on one tick scatter differently.
var _use_index: int = 0

## Set while re-running inputs after a correction.
var _replaying: bool = false

var _ready_for_use: bool = false


## [param authored_ticks], a count off [param def], as a count at [member tick_rate].
##
## The one place a definition's durations meet the running rate. Public so a layer over
## the arsenal (a rig's presentation, an alt-fire it runs itself) times its own half by
## the same numbers instead of reading the raw field and drifting at another rate.
func ticks_for(def: DotWeaponDef, authored_ticks: int) -> int:
	if def == null:
		return authored_ticks
	return def.ticks_at(authored_ticks, tick_rate)


## [param def]'s charge after [param ticks_held] ticks at [member tick_rate].
func charge_for(def: DotWeaponDef, ticks_held: int) -> float:
	if def == null:
		return 1.0
	return def.charge_at(ticks_held, tick_rate)


func carries(id: StringName) -> bool:
	for slot: DotWeaponSlot in _slots.values():
		if slot.id() == id:
			return true
	return _shelf_has(0, id)


func has_slot(slot: int) -> bool:
	return _slots.has(slot)


func slot_at(slot: int) -> DotWeaponSlot:
	return _slots.get(slot, null)


func current_slot() -> int:
	return _current


func current() -> DotWeaponSlot:
	return _slots.get(_current, null)


func current_def() -> DotWeaponDef:
	var slot := current()
	return slot.def if slot != null else null


func slots() -> Array[int]:
	var out: Array[int] = []
	for key: int in _slots.keys():
		out.append(key)
	out.sort()
	return out


func ammo() -> DotWeaponAmmo:
	return _ammo


## Weapons one slot may hold.
func slot_capacity() -> int:
	return carry.slot_capacity if carry != null else 1


## Every weapon in [param slot], the one in hand first.
func weapons_in(slot: int) -> Array[DotWeaponSlot]:
	var out: Array[DotWeaponSlot] = []
	if _slots.has(slot):
		out.append(_slots[slot])
		out.append_array(_shelf_of(slot))
	return out


## Total weight carried now.
func carried_weight() -> float:
	if carry == null:
		return 0.0
	var total := 0.0
	for s: int in _slots:
		for w in weapons_in(s):
			total += carry.weight_of(w.def)
	return total


## The most this carrier may carry now; INF with no carry rules.
func capacity() -> float:
	return carry.limit_for(backpack_tier) if carry != null else INF


## Weight over [method capacity], 0 when under.
func over_by() -> float:
	return maxf(carried_weight() - capacity(), 0.0)


## Speed multiplier for the weight carried (1 unless the carry rule is SLOW and this is over).
func speed_scale() -> float:
	return carry.speed_scale(carried_weight(), capacity()) if carry != null else 1.0


## Wears a backpack of [param tier] if it is bigger than the one worn. False when it is not an upgrade.
func equip_backpack(tier: int) -> bool:
	if carry == null or tier <= backpack_tier or tier > carry.max_backpack_tier():
		return false
	backpack_tier = tier
	carried_changed.emit()
	return true


func _shelf_of(slot: int) -> Array:
	if not _shelf.has(slot):
		_shelf[slot] = []
	return _shelf[slot]


func _shelf_has(slot: int, id: StringName) -> bool:
	for s: int in _shelf:
		if slot != 0 and s != slot:
			continue
		for w: DotWeaponSlot in _shelf[s]:
			if w.id() == id:
				return true
	return false


func _shelf_drop(slot: int, id: StringName) -> void:
	var behind := _shelf_of(slot)
	for i in behind.size():
		if (behind[i] as DotWeaponSlot).id() == id:
			behind.remove_at(i)
			return
