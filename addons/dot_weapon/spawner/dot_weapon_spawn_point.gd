class_name DotWeaponSpawnPoint
extends Node3D

## The marker a mapper places: it names a spawner, and a [DotWeaponSpawner] reads it as a [DotWeaponSpawnSite].
##
## It draws and simulates nothing; the server's spawner decides, a client draws from [DotWeaponSpawnView]. Fields left at their defaults can be set from the config by [member spawner_id].

const GROUP := &"dot_weapon_spawn_points"

@export var spawner_id: StringName = &""
@export var pool: StringName = &""
@export var item: StringName = &""
@export var kind: StringName = &""
## Comma-separated tag lists narrowing the pool.
@export var tags_any: String = ""
@export var tags_all: String = ""
@export var tags_none: String = ""
@export var respawn_seconds: float = 30.0
@export_range(0.0, 1.0) var respawn_jitter: float = 0.0
@export var initial_delay: float = 0.0
@export var max_alive: int = 1
@export var one_shot: bool = false
@export var lifetime_seconds: float = 0.0
@export var group: StringName = &""
@export var enabled: bool = true


func _ready() -> void:
	add_to_group(GROUP)


## The site this marker stands for; an empty [member spawner_id] becomes the node's name.
func to_site() -> DotWeaponSpawnSite:
	var d := {
		"id": spawner_id if spawner_id != &"" else StringName(name), "position": global_position if is_inside_tree() else position,
		"rotation_y": rotation.y, "kind": kind, "pool": pool, "item": item, "respawn_seconds": respawn_seconds,
		"respawn_jitter": respawn_jitter, "initial_delay": initial_delay, "max_alive": max_alive, "one_shot": one_shot,
		"lifetime_seconds": lifetime_seconds, "group": group, "enabled": enabled,
	}
	for key in ["tags_any", "tags_all", "tags_none"]:
		if str(get(key)).strip_edges() != "":
			d[key] = get(key)
	return DotWeaponSpawnSite.from_dictionary(d)


## Every marker under [param root] as a site.
static func collect(root: Node) -> Array[DotWeaponSpawnSite]:
	var out: Array[DotWeaponSpawnSite] = []
	for n in root.find_children("*", "Node3D", true, false):
		if n is DotWeaponSpawnPoint:
			out.append((n as DotWeaponSpawnPoint).to_site())
	return out
