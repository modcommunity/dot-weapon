extends RefCounted

## dot-weapon's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.
##
## 2: [member DotWeaponDef.authored_tick_rate] with [method DotWeaponDef.ticks_at],
## [method DotWeaponDef.per_tick_at] and [method DotWeaponDef.scales_at];
## [method DotWeaponArsenal.ticks_for] and [method DotWeaponArsenal.charge_for];
## [method DotWeaponBehaviour.scaled_ticks], [method DotWeaponBehaviour.scaled_per_tick]
## and [method DotWeaponBehaviour.running_tick_rate]. A pack whose definitions set the
## rate fails to compile on a host built before it. OLDEST stays 1: a definition that
## names no rate behaves exactly as before.

## 3: [method DotWeaponCatalogue.follow_content] and [method DotWeaponCatalogue.unfollow_content]
## (weapons delivered by mounted content packs, session-aware), [DotWeaponListing] with
## [method DotWeaponCatalogue.listings], [method DotWeaponCatalogue.listing] and
## [method DotWeaponCatalogue.categories], the [signal DotWeaponCatalogue.weapon_added] and
## [signal DotWeaponCatalogue.listings_changed] signals, and the optional category and icon arguments of
## [method DotWeaponCatalogue.add]. Needs dot-core API 9 ([DotContentIndex]); OLDEST stays 1.

## 4: weapon attachments ([member DotWeaponDef.mounts], [DotWeaponAttachment], [DotWeaponFitting], [DotWeaponAttachments],
## [method DotWeaponArsenal.fit], [method DotWeaponArsenal.fitting_at], [method DotWeaponNetSync.fitting_specs]). OLDEST stays 1.

## 5: [DotWeaponProfiles], weapons as `weapon` profiles (dot-core [DotProfileSet]) with upgrade children.
## Needs dot-core API with DotProfileSet; OLDEST stays 1.

## 6: [DotWeaponProfileGroup] (every pack's weapon set behind the one `weapon` kind, one runtime layer),
## the optional `layer` of [method DotWeaponProfiles.make_set] and [method DotWeaponProfiles.refresh_def].
## OLDEST stays 1.

## 7: [method DotWeaponProfiles.profile_schemas]. OLDEST stays 1.

## 8: the overlay on code-built defs in [DotWeaponProfiles]: `overlay_set`, `tune`, `file_flat`, `apply_flat`,
## `flat_of`, `to_yaml`, `profile_path`, `upgraded`. OLDEST stays 1.

## 9: spawners (`spawner/`, docs/spawners.md): [DotWeaponSpawner], [DotWeaponSpawnView], [DotWeaponSpawnPool],
## [DotWeaponSpawnSite], [DotWeaponSpawnPoint], [DotWeaponSpawnerConfig]. OLDEST stays 1.

## 10: carry weight ([DotWeaponCarry], `DotWeaponDef.weight`, `weight` profile key; arsenal `carry`, `backpack_tier`,
## `cycle_slot`, `weapons_in`, `carried_weight`, `capacity`, `enforce_limit`). Off unless a game sets `carry`. OLDEST stays 1.

## 11: selectable fire modes: [member DotWeaponDef.fire_modes] (and the `fire_modes` profile key),
## [method DotWeaponArsenal.cycle_fire_mode], `set_fire_mode`, `fire_mode`, `fire_modes_available`, the
## [signal DotWeaponArsenal.fire_mode_changed] signal and [constant DotWeaponCommand.BUTTON_FIRE_MODE]
## (the command is one bit wider). OLDEST stays 1.

## 12: [DotWeaponMuzzle] and the `muzzle_flash` key under `extra:`. OLDEST stays 1.

## 13: ammo types and hit-zone armour for simulated bullets: [DotWeaponAmmoType], [DotWeaponAmmoTypes] (`ammo`
## profile kind), [DotWeaponHitzones], `DotWeaponBulletBridge.ammo_types`/`hitzones`, `arsenal.load_ammo`/`ammo_of`.
## Inert unless `sv_ballistics` is on and a game sets them. OLDEST stays 1.

## 14: [method DotWeaponArsenal.equip], a hand-out that holds a slot at once even while the arsenal is disabled. OLDEST stays 1.

## 15: the accuracy model: [DotWeaponAccuracyClass] presets, the "Accuracy model" and recoil posture fields of
## [DotWeaponBallistics] (-1 takes the class), bloom delay, settle, flinch, `sv_spread_scale`. OLDEST stays 1.

## 16: [method DotWeaponDef.selector_modes], the fire-mode list a pack gives an automatic or burst gun. OLDEST stays 1.

## 17: [method DotWeaponNetSync.fire_mode_specs] takes owner_only, [method DotWeaponNetSync.fire_mode_will_change], push's with_fire_mode. OLDEST stays 1.

## 18: [DotWeaponUseKey], the shared E-key rules over a dropped weapon (tap/hold); a tap on a different weapon now replaces it. OLDEST stays 1.

## 19: [DotWeaponWheel], the shared previous/next weapon wheel over a ring of slots (mouse wheel or pad). OLDEST stays 1.

## 20: [DotWeaponDropKey], the drop key with an opt-in hold (`sv_weapon_drop_key_hold`, `drop_key_hold` per class; 0 = on the press). OLDEST stays 1.

## 21: [method DotWeaponNetSync.correct_fire_mode], the owner's predicted selector yields to the server after a few mismatching snapshots. OLDEST stays 1.

## 22: [member DotWeaponArsenal.crosshair_cone], false lets a carrier nobody watches skip the context on idle ticks with spread rules attached. OLDEST stays 1.

## 23: [member DotWeaponArsenal.idle_posture], a cheap posture-only context so an idle tick with enabled spread rules builds no full one. OLDEST stays 1.

## 24: [member DotWeaponArsenal.idle_still] and [method DotWeaponBehaviour.rest_tick], an idle weapon at rest on a settled carrier skips its tick (identical state; assigning a bridge `posture_for` to `idle_posture` sets it). OLDEST stays 1.

## 25: [method DotWeaponDrops.scan] and the cleanup rules [member DotWeaponDropRules.scan_interval] and [member DotWeaponDropRules.evict] (cvars sv_weapon_drop_scan, sv_weapon_drop_evict); lifetime expiry now runs on the scan, defaults are 120 s and a 10 s scan. OLDEST stays 1.

## 26: `view/dot_weapon_iron_sight.gd` (by path, no `class_name`): the sight line measured from a gun mesh and the iron sight built on it, UV spread included; zee-dot-weapons and arena-weapons preload it instead of each carrying a copy. OLDEST stays 1.
## 27: `thrown/` [DotWeaponKnives] (a thrown-knife layer: aim-key throw, flight, bounce, kill-and-stick, pickup, client mirror and drawing; rules `enabled`/`speed`/`pickup`/`damage`, `bind_cvars`) and [DotWeaponKnifeWire] (its event body, over a writer/reader the game passes). OLDEST stays 1.
## 28: `view/dot_weapon_scope_overlay.gd` and `view/dot_weapon_scope_prefs.gd` (by path, no `class_name`): the scope overlay (circle, reticle, lens and full-screen modes, walk-clear), duck-typed on the view model, and the cl_scope_mode and cl_scope_walk_clear cvars with their statics; arena-weapons and zee-dot-weapons subclass it. OLDEST stays 1.
## 29: `view/dot_weapon_scope_view.gd` (by path, no `class_name`): the scope-view rules (resolve the player's mode against a server pin, lens test, camera FOV scale, walking clear) that arena-weapons and zee-dot-weapons view models call instead of each mirroring them. OLDEST stays 1.
## 30: `view/dot_weapon_reload_shots.gd` (by path, no `class_name`): the fractions, the wait for a rig to reach one and the contact sheet of a first-person reload review (game-zombie-zone `shot.sh --view=reload`). OLDEST stays 1.
## 31: `DotWeaponArsenal.is_cooling_for(command, ctx)`: whether this tick reads nothing of the context's aim (a trigger held inside the cadence), so a rig can skip working the aim out.
## 32: `DotWeaponArsenal.phase_timers`, `phase_us`, `phase_calls`, `PHASES`: opt-in sub-phase timings of simulate_tick and idle_tick for a profiler. OLDEST stays 1.
const LEVEL := 32
const OLDEST := 1
