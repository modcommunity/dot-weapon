class_name DotWeaponNetSync
extends RefCounted

## What a networked carrier has to replicate of its [DotWeaponArsenal], and how to move
## it in and out.
##
## The weapon half of what dot-combat's `DotCombatNetSync` used to carry on its own. A
## game using both concatenates the two spec lists; a game with weapons and no health
## uses only this one.
##
## [b]dot-net is not a dependency and is not imported here[/b], for the reason
## dot-combat gives: a script that merely [i]mentions[/i] a [code]class_name[/code] the
## project does not have fails to parse, and takes every script referencing it down as
## well. So the bridge lives in the host game and this is everything it would otherwise
## have to work out.
##
## [b]Ammunition is owner-only, and that is not a bandwidth optimisation.[/b] Exact
## magazine and reserve counts are information an opponent should not have, and sending
## them to everyone is how a modified client knows when to push.

const SLOT_BITS := 5
const MAGAZINE_BITS := 9
const RESERVE_BITS := 11


static func specs() -> Array[Dictionary]:
	return [
		{
			"property": &"net_slot",
			"type": "UINT",
			"bits": SLOT_BITS,
			"owner_only": false,
			"interpolated": false,
		},
		{
			"property": &"net_magazine",
			"type": "UINT",
			"bits": MAGAZINE_BITS,
			"owner_only": true,
			"interpolated": false,
		},
		{
			"property": &"net_reserve",
			"type": "UINT",
			"bits": RESERVE_BITS,
			"owner_only": true,
			"interpolated": false,
		},
	]


static func properties() -> Array[StringName]:
	var out: Array[StringName] = []
	for spec in specs():
		out.append(spec["property"])
	return out


## Copies the arsenal's state onto a replicating object.
static func pull(arsenal: DotWeaponArsenal, target: Object) -> void:
	if target == null or arsenal == null:
		return

	target.set(&"net_slot", clampi(arsenal.current_slot(), 0, (1 << SLOT_BITS) - 1))

	var slot := arsenal.current()

	if slot == null:
		target.set(&"net_magazine", 0)
		target.set(&"net_reserve", 0)
		return

	target.set(
		&"net_magazine", clampi(slot.magazine, 0, (1 << MAGAZINE_BITS) - 1)
	)
	target.set(
		&"net_reserve",
		clampi(arsenal.ammo().count(slot.def.ammo_type), 0, (1 << RESERVE_BITS) - 1)
	)


## Applies received state on a peer that is not authoritative.
##
## [b]Only the slot is written straight through.[/b] Which weapon somebody is holding
## is public and is the server's to decide, so a viewer draws what it is told. The
## counts are not written here at all: a non-owner has no business displaying another
## player's exact magazine, and the owner is predicting its own and would have that
## prediction undone on every single snapshot.
static func push(source: Object, arsenal: DotWeaponArsenal) -> void:
	if source == null or arsenal == null:
		return

	var slot := int(source.get(&"net_slot"))

	if slot > 0 and slot != arsenal.current_slot() and arsenal.has_slot(slot):
		arsenal.select(slot, 0)


## Applies an authoritative ammunition correction to a predicted arsenal.
##
## Called by the owning client when reconciliation says its prediction was wrong.
## Separate from [method push] because a non-owner has no prediction to correct and
## must not have its display overwritten by somebody else's ammunition.
static func correct_ammo(source: Object, arsenal: DotWeaponArsenal) -> void:
	if source == null or arsenal == null:
		return

	var slot := arsenal.current()

	if slot == null:
		return

	slot.magazine = int(source.get(&"net_magazine"))

	if slot.def.ammo_type != &"":
		arsenal.ammo().set_count(
			slot.def.ammo_type, int(source.get(&"net_reserve"))
		)


## Bits one carrier's weapon state costs. For a bandwidth estimate.
static func estimated_bits() -> int:
	return SLOT_BITS + MAGAZINE_BITS + RESERVE_BITS
