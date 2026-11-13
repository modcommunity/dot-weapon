# Weapon attachments

Attachments are items of their own: a scope, a suppressor, a laser, an extended magazine. One attachment fits every weapon its rules allow, so nothing is wired to one gun. dot-weapon holds the generic part (schema, fit rules, the server request, the menu, loadout rows and model sockets). A weapon pack provides only the profile files and meshes.

## Pieces

| Class | Role |
| --- | --- |
| `DotWeaponAttachment` | one attachment: mount, fit rules, `scale`/`add` on def or tuning fields, `params.` the presentation reads, the inventory `item`, the `model` scene |
| `DotWeaponFitting` | what is on one gun, as ids per mount |
| `DotWeaponAttachments` | the catalogue: `load_set` (the `attachment` profile kind), `choices_for`, `toggle`, `apply` (copy-on-apply), `stat_delta`, `for_item`, the packed wire code |
| `DotWeaponAttachRequest` | a client's ask `[slot, mount, id]`; only the server applies it |
| `DotWeaponAttachMenu` | the attach/detach menu (keyboard, pad, touch); emits `requested`, changes nothing |
| `DotWeaponAttachmentModels` | `dress(weapon_model, catalogue, fitting)` puts each attachment's scene under `socket_<mount>` |
| `DotWeaponLoadoutBridge` | `fill` fits attachment rows after the weapons; `fitted_rows` gives the rows to save |

## Profiles

A pack ships one file per attachment at `<root>/addon/<pack>/attachment/<id>.yml`:

```yaml
name: "Suppressor"
description: "Quieter and no flash; a little less damage at range."
mount: "muzzle"
item: "item_suppressor"
model: "res://weapons/attachments/suppressor.tscn"
fits_tags: "rifle,smg,pistol"
excludes_tags: "shotgun"
tags_added: "quiet"
scale:
  damage: 0.9
  recoil_pitch: 0.85
  falloff_start: 0.8
params:
  suppressed: true
  muzzle_flash: "none"
```

`item` defaults to the attachment id. `scale` multiplies and `add` adds to def fields (`magazine`, `recoil_pitch`, `spread`, `falloff_start`, ...), tuning fields, or `params.<key>`.

## Compatibility

An attachment fits a weapon when all of these hold:

- the weapon has its `mount` (in the def's mounts);
- `fits_slots` is empty or holds its slot;
- `fits_tags` and `fits_weapons` are both empty, or the weapon has one of the tags or is one of the named weapons;
- the weapon has none of `excludes_tags`;
- nothing already fitted `blocks` this mount, and this one does not block a mount already in use.

`toggle` is the only way to change a fitting. It answers with a DotResult: `CODE_FORBIDDEN` when it does not fit, `CODE_CONFLICT` for a wrong mount or a block.

## Presentation params

The view reads these from the fitted def's `params`. The simulation never reads them.

| Key | Meaning |
| --- | --- |
| `optic_zoom` | the scope's magnification; the view's scope code uses it for its FOV |
| `optic_reticle` | the reticle texture or name the scope overlay draws |
| `ads_seconds` | the aim-down-sights time |
| `suppressed` | the game plays the suppressed shot sound |
| `muzzle_flash` | the flash variant; `"none"` shows none |

## Server flow

1. The menu emits `requested(mount, id)`.
2. The client sends `DotWeaponAttachRequest.make(slot, mount, id).to_wire()` over its own RPC.
3. The server runs `from_wire`, then `apply(arsenal, owns)`, where `owns` is an inventory lookup. It checks ownership and fit, then calls `arsenal.fit`.
4. The fitting reaches every machine through net sync, and the client calls `menu.show_fitting`.

The fitted def is the one the slot's behaviour fires with. Hit registration and lag compensation therefore only ever see a server fitting, and server and client compute identical shots from it.

## Loadouts

A resolved loadout row whose item is an attachment (`for_item`) is fitted after the weapons: on its `arsenal_slot`, or with none on the first carried weapon it fits. A row that no longer fits is dropped, never an error. `fitted_rows(arsenal)` returns the `{arsenal_slot, item}` rows to save.

## Models

A weapon model marks its mounts with nodes named `socket_<mount>` (`socket_muzzle`, `socket_optic`, ...). `DotWeaponAttachmentModels.dress` instances each fitted attachment's `model` there and replaces what it placed earlier. A weapon without the socket shows nothing. `examples/attach_demo.tscn` is the render check (`tools/screenshot.sh out.png res://examples/attach_demo.tscn`).

Meshes must be free (CC0) or our own.
