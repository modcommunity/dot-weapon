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

## 11: selectable fire modes: [member DotWeaponDef.fire_modes] (and the `fire_modes` profile key), [method
## DotWeaponArsenal.cycle_fire_mode], `set_fire_mode`, `fire_mode`, `fire_modes_available`, [signal DotWeaponArsenal.fire_mode_changed]
## and [constant DotWeaponCommand.BUTTON_FIRE_MODE] (the command is one bit wider). OLDEST stays 1.

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

## 26: `view/dot_weapon_iron_sight.gd` (by path, no `class_name`): the sight line measured from a gun mesh and the iron sight built on it, UV spread included; zee-dot-weapons and fc-weapons preload it instead of each carrying a copy. OLDEST stays 1.
## 27: `thrown/` [DotWeaponKnives] (a thrown-knife layer: aim-key throw, flight, bounce, kill-and-stick, pickup, client mirror and drawing; rules `enabled`/`speed`/`pickup`/`damage`, `bind_cvars`) and [DotWeaponKnifeWire] (its event body, over a writer/reader the game passes). OLDEST stays 1.
## 28: `view/dot_weapon_scope_overlay.gd` and `view/dot_weapon_scope_prefs.gd` (by path, no `class_name`): the scope overlay (circle, reticle, lens and full-screen modes, walk-clear), duck-typed on the view model, and the cl_scope_mode and cl_scope_walk_clear cvars with their statics; fc-weapons and zee-dot-weapons subclass it. OLDEST stays 1.
## 29: `view/dot_weapon_scope_view.gd` (by path, no `class_name`): the scope-view rules (resolve the player's mode against a server pin, lens test, camera FOV scale, walking clear) that fc-weapons and zee-dot-weapons view models call instead of each mirroring them. OLDEST stays 1.
## 30: `view/dot_weapon_reload_shots.gd` (by path, no `class_name`): the fractions, the wait for a rig to reach one and the contact sheet of a first-person reload review (game-zombie-zone `shot.sh --view=reload`). OLDEST stays 1.
## 31: `DotWeaponArsenal.is_cooling_for(command, ctx)`: whether this tick reads nothing of the context's aim (a trigger held inside the cadence), so a rig can skip working the aim out.
## 32: `DotWeaponArsenal.phase_timers`, `phase_us`, `phase_calls`, `PHASES`: opt-in sub-phase timings of simulate_tick and idle_tick for a profiler. OLDEST stays 1.
## 33: ammo profiles `speed` and `reference_speed` (m/s, 0 = off) reach `DotPenetration.speed`/`reference_speed` through `make_penetration`; dot-combat scales wall and body costs by them. OLDEST stays 1.
## 34: `DotWeaponHitscan.steady_skip` (static, on): a hitscan weapon whose idle tick left its spread state at a fixed point skips the spread work on the next tick with the same inputs (posture, motion, rules, cone, tuning, no flinch), identical state; off for A/B. OLDEST stays 1.
## 35: `DotWeaponHitscan` reads the cone's accuracy terms as the field or the class preset kept with the class (no by-name `accuracy()` lookups), and a slowing carrier's settle the same way: an idle moving carrier's tick is cheaper, identical cone (`_test_accuracy_cone_reads`). OLDEST stays 1.
## 36: [member DotWeaponDropRules.rescue] (cvar sv_weapon_drop_rescue, on): a moving drop whose centre passed down through a floor since the last tick is put back on top of it, and one that fell [constant DotWeaponDrops.RESCUE_DEPTH] below its drop point goes back there once, then is removed. OLDEST stays 1.
## 37: the drop rescue finds floors by back faces too (a trimesh wound the other way was missed, so its tunnels fell 40 m), and a drop [constant DotWeaponDrops.RESCUE_DEPTH] below its drop point goes back on the floor under that point, frozen there the second time; only a drop with no floor under its point is removed. OLDEST stays 1.
## 38: attachments as items with a server-side request: `DotWeaponAttachment` fits_slots/excludes_tags/blocks/item_id/model and `params.` fields, `DotWeaponAttachments` KIND/schema/load_set/for_item/toggle/stat_delta, `DotWeaponAttachRequest`, `DotWeaponAttachMenu`, `DotWeaponAttachmentModels`, loadout attachment rows; a fitted slot's behaviour now fires the fitted def. OLDEST stays 1.
## 39: [member DotWeaponDrops.rng] and [method DotWeaponDrops.seed_rng]: drops roll, spin, tumble and evict on their own stream, randomised per layer (live play as before) or seeded from a match or sim seed so a bot sim repeats; nothing in drops reads the global stream. OLDEST stays 1.
## 40: [member DotWeaponDropRules.settle_max_sec] (cvar sv_weapon_drop_settle_max, default 4.0, 0 never forces a rest) and [member DotWeaponDropRules.refall_max] (sv_weapon_drop_refall_max, default 4, 0 unlimited) replace the hardcoded [constant DotWeaponDrops.SETTLE_MAX_SEC] and [constant DotWeaponDrops.REFALL_MAX], which stay as the defaults. A value out of range is refused (cvar) or reported as an error by [method DotWeaponDropRules.problems] (direct), never clamped. Additive. OLDEST stays 1.
## 41: [DotWeaponKnives] charged throws (rules `charge`, `charge_sec`, `charge_min`; [method DotWeaponKnives.charge_of], [method DotWeaponKnives.power_fraction], [method DotWeaponKnives.fill_fraction]) and the Boomerang ([constant DotWeaponKnives.PARAM_BOOMERANG] on a fitted def; rules `boomerang_loop` (replaced at 43), `boomerang_to_thrower`, `boomerang_left`; [method DotWeaponKnives.glides], [method DotWeaponKnives.turn_of], [method DotWeaponKnives.is_boomerang]); `mirror` and [method DotWeaponKnifeWire.write_knife] take optional glide and turn, `read_knife` returns them. A returned or picked-up knife keeps its fitting. Additive, `charge` defaults off. OLDEST stays 1.
## 42: [member DotWeaponHitscan.native_tick] (default on): a context tick runs dot-sim's DotSimWeaponSpread (found through ClassDB, never named) when it is loaded, bit-exact with the GDScript tick it replaces, which stays the fallback (dot-sim absent, a refused row, or `native_tick = false` for A/B). The native path keeps no steady fixed point. [member DotWeaponBallistics.accuracy_revision] and [member DotWeaponSpreadRules.revision] count field writes so the native rows refresh only on a change. Additive. OLDEST stays 1.
## 43: the Boomerang flies out, circles and returns: rules `boomerang_distance` (metres straight out, 0 flies straight on), `boomerang_radius` (turn radius, 0 turns on the spot), `boomerang_speed` (0 uses the throw speed) replace `boomerang_loop`; the path is a function of the metres flown, closes on the throw point exactly and ignores the thrower's own velocity; the wire carries the turn only on the circling leg. Additive.
## 44: [method DotWeaponArsenal.idle_tick_row] and [method DotWeaponBehaviour.idle_row]: an idle tick handed its posture as a packed row and its stillness as a bool, which [DotWeaponHitscan] runs as one native call (rest tick or posture tick, bit-exact with [method DotWeaponArsenal.idle_tick], which stays the fallback). Additive. OLDEST stays 1.
## 45: rule `boomerang_catch` (cvar suffix `_boomerang_catch`, default 1.5 m, 0 never): a Boomerang on its return leg is caught in the air when it passes within that reach of its thrower's hand (alive, no knife), back in the hand with its fitting instead of falling at the throw point. Additive. OLDEST stays 1.
## 46: [method DotWeaponArsenal.empty_hand] (lowers the weapon in hand at once, slot 0) and knives rule `boomerang_empty_hand` (cvar suffix `_boomerang_empty_hand`, default on): a Boomerang thrower waits for the catch bare-handed instead of drawing the next weapon; the catch puts the knife back in hand, a knife that falls, sticks or is taken brings the first carried weapon up. Additive. OLDEST stays 1.
## 47: [method DotWeaponBehaviour.idle_row_framed] and [method DotWeaponBehaviour.tick_needs_context_posed]: [method DotWeaponArsenal.idle_tick_row] hands the behaviour its rules, crosshair and rate, and [method DotWeaponArsenal.is_idle_for] says a posture is provided, so a hitscan whose cached native rows provably still hold skips re-reading and re-checking them. [member DotWeaponBehaviour.idle_gate] (1 default; 0 the plain calls for A/B; 2 verify, counting [member DotWeaponBehaviour.idle_gate_misses]). Bit-exact. Additive. OLDEST stays 1.
const LEVEL := 47
const OLDEST := 1
