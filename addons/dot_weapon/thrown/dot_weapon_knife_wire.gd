class_name DotWeaponKnifeWire
extends RefCounted
## The wire format of one [DotWeaponKnives] event: id, owner, phase, victim, where and how it moves.
## dot-net's writer and reader are passed in, never named (dot-net is not a dependency of dot-weapon):
## [code]writer[/code] is a DotNetWriter, [code]reader[/code] a DotNetReader.

const _EXTENT := 4096.0


## Appends the body of one knife event to [param w]; the game writes its own sub-kind first.
static func write_knife(w, id: int, owner: int, phase: int, victim: int, at: Vector3, motion: Vector3) -> void:
	w.write_varint(id)
	w.write_varint(maxi(0, owner))
	w.write_uint(clampi(phase, 0, 3), 2)
	w.write_varint(maxi(0, victim))
	w.write_vector3_range(at, -_EXTENT, _EXTENT, 20)
	w.write_vector3_range(motion, -64.0, 64.0, 12)


## Reads what [method write_knife] wrote; "ok" says the reader did not run short.
static func read_knife(reader) -> Dictionary:
	var out := {"id": reader.read_varint(), "owner": reader.read_varint(), "phase": reader.read_uint(2), "victim": reader.read_varint()}
	out["at"] = reader.read_vector3_range(-_EXTENT, _EXTENT, 20)
	out["motion"] = reader.read_vector3_range(-64.0, 64.0, 12)
	out["ok"] = reader.ok()
	return out
