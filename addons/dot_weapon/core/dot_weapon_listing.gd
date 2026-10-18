class_name DotWeaponListing
extends RefCounted

## One row of a weapon menu: what a spawn menu, a loadout screen or a console needs to show
## a weapon without loading its definition, its behaviour or its art.
##
## [b]Why a separate object from [DotWeaponDef].[/b] A definition is the simulation's
## document and carries nothing a menu wants (no category, no thumbnail, no pack). Putting
## those on the definition would make every pack author's `.tres` carry presentation the
## server never reads, and would leave code-registered weapons with nothing to say where
## they came from. The listing is the join of the two, built by [DotWeaponCatalogue].

## The weapon's id: [member DotWeaponDef.id], which is also the published entry's id.
var id: StringName = &""

var display_name: String = ""

## A menu grouping. The pack's category id for a delivered weapon, whatever
## [method DotWeaponCatalogue.add] was given for a code one, "" for none.
var category: String = ""

## Path of the thumbnail image ("" when there is none). A path, not a Texture, so listing
## a hundred weapons loads no image; [method icon] loads one on demand.
var icon_path: String = ""

## Where the definition lives: a `res://` path on a mount for a delivered weapon, "" for one
## registered from code.
var def_path: String = ""

var slot: int = 1
var tags: PackedStringArray = PackedStringArray()

## The entry's free `meta` dictionary (zee's `asset_root`, for one). Empty for code weapons.
var meta: Dictionary = {}

## [code]&"game"[/code] for a code weapon, else the index entry's source
## (`&"subscription"`, `&"server"`).
var source: StringName = &"game"

## Delivering pack ("" for code weapons).
var content_id: String = ""
var version: String = ""
var pack_title: String = ""

## [member DotContentEntry.key] for a delivered weapon, "" for code ones.
var entry_key: String = ""

## The definition itself. Always set: delivered definitions are loaded when the listing is
## made, because a row that cannot load is rejected rather than shown and failing on click.
var def: DotWeaponDef = null


func is_delivered() -> bool:
	return entry_key != ""


## The thumbnail, or null when there is none or it does not load.
func icon() -> Texture2D:
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return null
	return load(icon_path) as Texture2D


func describe() -> Dictionary:
	return {
		"id": String(id), "name": display_name, "category": category, "slot": slot,
		"source": String(source), "pack": content_id, "def": def_path,
	}
