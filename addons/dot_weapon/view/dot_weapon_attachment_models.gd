class_name DotWeaponAttachmentModels
extends RefCounted

## Puts the models of a fitting on a weapon model: each attachment's [member DotWeaponAttachment.model]
## goes under the node named `mount_<mount>`. Pure presentation; a weapon with no such node shows nothing.

const SOCKET_PREFIX := "mount_"
const _META := &"dot_attachment_model"


## Replaces what an earlier call placed under [param weapon_model]; returns how many models it placed.
static func dress(weapon_model: Node, catalogue: DotWeaponAttachments, fitting: DotWeaponFitting) -> int:
	if weapon_model == null:
		return 0
	for old in weapon_model.find_children("*", "", true, false):
		if old.has_meta(_META):
			old.get_parent().remove_child(old)
			old.queue_free()
	if catalogue == null or fitting == null:
		return 0
	var placed := 0
	for mount in fitting.mounts():
		var att := catalogue.get_attachment(fitting.attachment_on(mount))
		var socket := weapon_model.find_child(SOCKET_PREFIX + String(mount), true, false)
		if att == null or att.model == "" or socket == null or not ResourceLoader.exists(att.model):
			continue
		var scene := load(att.model) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate()
		node.set_meta(_META, att.id)
		socket.add_child(node)
		placed += 1
	return placed
