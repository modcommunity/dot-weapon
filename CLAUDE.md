# dot-weapon

What a player holds and uses. A weapon is a document (`DotWeaponDef`) that names a behaviour script by path; the arsenal runs slots, cadence, ammunition and reloads, and the behaviour decides what a use does, returning shots for dot-combat and spawns for the game.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_weapon/`.** It requires [dot-core](../dot-core) and [dot-combat](../dot-combat) (symlinked into `addons/`, gitignored). dot-net, dot-loadout, dot-inventory and dot-player are optional and never named.

Also requires **dot-profile** (`DotProfileSet`, `DotProfile`, `DotProfileRuntime`, split from dot-core): link `addons/dot_profile` next to `addons/dot_core`.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing anything: why a definition plus a behaviour, the four behaviour rules, ticks, the `_try_use` order, `select()`, spread and recoil, `DotShot`, the duck-typed bridges |
| [docs/history.md](docs/history.md) | the dot-combat split, and the two bugs that left rules here |

## Layout

| Path | What |
| --- | --- |
| `core/dot_weapon_def.gd` | `DotWeaponDef`: `authored_tick_rate`, slot, deploy/holster ticks, `Fire` mode, cost, reload, `behaviour_path`, `params`, `tuning` |
| `dot_weapon_api.gd` | the API level ([DotAddonApi](../dot-core/addons/dot_core/core/dot_addon_api.gd)); 2 = `authored_tick_rate` and the scaling helpers; 3 = `follow_content` and the menu listings; 6 = `DotWeaponProfileGroup`; 7 = `profile_schemas` |
| `core/` (rest) | `DotWeaponCatalogue` (code weapons plus `follow_content(index)` for weapons delivered by mounted packs, session-aware), `DotWeaponListing` (a menu row), `DotWeaponCommand` (the per-tick input), `DotWeaponContext`, `DotWeaponOutcome`, `DotWeaponSpawn`, `DotWeaponSlot`, `DotWeaponAmmo` |
| `behaviour/` | `DotWeaponBehaviour` (the extension point) and the stock `DotWeaponHitscan`, `DotWeaponProjectile`, `DotWeaponMelee`, `DotWeaponBeam`, `DotWeaponThrown` |
| `tuning/` | `DotWeaponTuning` (subclass for typed fields), `DotWeaponBallistics` (what the gun-like behaviours read) and `DotWeaponAccuracyClass` (per-class defaults for its -1 accuracy and recoil fields, API 15; `DotWeaponDef.selector_modes` is the pack helper for `fire_modes`, API 16; `DotWeaponNetSync.fire_mode_specs(false)` replicates the selector mode to everyone and `fire_mode_will_change` tells a mirror to click, API 17; [design](docs/design.md#the-accuracy-model)) |
| `runtime/dot_weapon_arsenal.gd` | `DotWeaponArsenal`: the state machine; `select`, `use`, `begin_reload`, snapshots; its signals, fields and read-only queries (carry weight, shelf) are in the base `dot_weapon_arsenal_state.gd`, restore in `dot_weapon_arsenal_io.gd` |
| `core/dot_weapon_attachment.gd`, `dot_weapon_fitting.gd`, `dot_weapon_attachments.gd` | attachments: a mod (`DotWeaponAttachment`), what is fitted to one gun as ids (`DotWeaponFitting`), the catalogue with fit rules, copy-on-apply and the packed wire code (`DotWeaponAttachments`); `arsenal.fit` uses them (API 4) |
| `core/dot_weapon_profiles.gd` | `DotWeaponProfiles`: the `weapon` profile kind (schema, `profile_schemas()` for dot-core's `profile_check` and dot-ci `profiles: true` (API 7), `flat`, `apply_common`, `menu_entries`, `upgrade_set`, `apply_upgrades`; and, for a pack that builds its defs in code, the overlay (API 8): `overlay_set`, `tune` (lays the profiles over the built defs, only the keys a file sets, `DotProfile.file_keys`), `flat_of`, `to_yaml`, `profile_path`, `upgraded`); a pack keeps its own keys under `extra:` (API 5); `core/dot_weapon_profile_group.gd` `DotWeaponProfileGroup`: all packs' sets behind one `weapon` kind and one runtime layer, so a runtime edit reaches every pack (API 6) |
| `core/dot_weapon_carry.gd` | `DotWeaponCarry` (API 10): one shared object per game, off by default: weight limit, multiplier, named modifiers (`set_modifier`), backpack tiers, slot capacity (several weapons per slot, `arsenal.cycle_slot`), over-limit SLOW or DROP; `DotWeaponDef.weight` is the per-weapon weight |
| `net/dot_weapon_net_sync.gd` | `DotWeaponNetSync`: slot, magazine, reserve specs (ammunition owner-only) |
| `spawner/` | [docs/spawners.md](docs/spawners.md): `DotWeaponSpawner` (server: sites, seeded draws, timers, caps), `DotWeaponSpawnView` (client), `DotWeaponSpawnPool`, `DotWeaponSpawnSite`, `DotWeaponSpawnPoint` (marker), `DotWeaponSpawnerConfig` (layered `spawner.yml`, `MAP_KEYS` for dot-map); suite `examples/spawner_selftest.tscn` (API 9) |
| `core/dot_weapon_ammo_type.gd`, `dot_weapon_ammo_types.gd`, `dot_weapon_hitzones.gd` | ammo types as `ammo` profiles and hit-zone armour for simulated bullets (API 13); optional on `DotWeaponBulletBridge`, inert unless `sv_ballistics` is on; [design](docs/design.md#ballistics) |
| `math/dot_weapon_recoil.gd` | `DotWeaponRecoil` |
| `math/dot_weapon_spread_rules.gd` | `DotWeaponSpreadRules`: movement-dependent spread as `sv_spread_*` cvars (bind_cvars / follow_cvars), off by default; multiplies the gun's own spread; `arsenal.spread_rules` set on both sides, `arsenal.spread_now()` is the cone a crosshair draws (the shot's own); `DotWeaponCommand.BUTTON_AIM` is the aim input; `sv_spread_mult_sprint` widens while `ctx.sprinting`, and `ctx.sprint_blocks_aim` (the controller's `sv_sprint_noaim`, via `motion()`) drops aim and reload |
| `math/dot_weapon_recoil_rules.gd` | `DotWeaponRecoilRules`: per-weapon recoil pattern as `sv_recoil_*` cvars (scale, vertical, horizontal, recovery, punch/bullet split, build, reset, aim/crouch/move/air), off by default; the kick is a pure function of the shot's index in a burst and a seed (`DotWeaponBallistics.recoil_seed`/`recoil_build`/`recoil_build_max`/`recoil_recovery`), so server bullet and client view agree; `arsenal.recoil_rules` on both sides; the outcome carries `recoil`, `recoil_recovery`, `recoil_signed` |
| `bridge/` | `DotWeaponLoadoutBridge` (dot-loadout to arsenal), `DotWeaponInventoryBridge` (bag to reserve), `DotWeaponPlayerBridge` (player to context, view-model mount), `DotWeaponMuzzle` (`extra.muzzle_flash` and dot-fx's flash, by path; [design](docs/design.md#muzzle-flash)) |
| `drops/` | `DotWeaponDrops` (server: thrown and death-dropped weapons as physics bodies, oldest-first cap, timed expiry, `take_for` into an empty slot; client: `mirror_*` copies) and `DotWeaponDropRules` (`sv_weapon_drop*` cvars, `resolve(class_def)` for per-class `drop_*` overrides, `follow_cvars`); suite `examples/drop_selftest.tscn` (4 sections, 35 checks) |
| `examples/weapon_selftest.tscn` | the suite; `fixtures/lightning_rod.gd` is the outside weapon it proves the extension point with |

Paths except `examples/` and `fixtures/` are in `addons/dot_weapon/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 180 godot --headless --path . res://examples/weapon_selftest.tscn` and `res://examples/spawner_selftest.tscn` (7 sections, 59 checks).

## Rules that bite

- Adding a weapon edits nothing here: a script extending `DotWeaponBehaviour`, a `DotWeaponDef` naming it by path, a catalogue row. [design](docs/design.md#the-one-idea)
- A behaviour is a pure function of the context: no clock, node, input device or random stream. [design](docs/design.md#four-rules-for-a-behaviour-and-they-all-break-quietly)
- A behaviour applies nothing; it returns a `DotWeaponOutcome`. [design](docs/design.md#four-rules-for-a-behaviour-and-they-all-break-quietly)
- Behaviour state lives in `state`, never a member, or a correction loses it. [design](docs/design.md#four-rules-for-a-behaviour-and-they-all-break-quietly)
- Check `ctx.replayed` before any sound, effect or statistic. [design](docs/design.md#four-rules-for-a-behaviour-and-they-all-break-quietly)
- Every duration on a definition is in ticks, at `authored_tick_rate` when set (0 = the running rate, unscaled); the arsenal reads them only through `ticks_for`/`charge_for`, a behaviour through `scaled_ticks`/`scaled_per_tick`. [design](docs/design.md#ticks-never-seconds)
- `DotWeaponOutcome.cooldown_ticks` is in the definition's ticks (the arsenal scales it); a `DotWeaponSpawn`'s fuse and life are in running ticks (the behaviour scales them). [design](docs/design.md#ticks-never-seconds)
- Client and server arsenals must share `tick_rate`; deadlines are absolute ticks in the snapshot. [design](docs/design.md#ticks-never-seconds)
- In `_try_use`, ask whether the weapon can pay before cancelling a reload. [design](docs/design.md#the-order-in-_try_use-is-load-bearing)
- `select()` refuses the slot a switch is already heading to; a game may send its slot every tick. [design](docs/design.md#select-refuses-the-slot-a-switch-is-already-heading-to)
- `DotSpread` stays in dot-combat; behaviours set `DotShot.spread`. [design](docs/design.md#spread-lives-in-dot-combat-not-here)
- Never name a class from dot-net, dot-loadout, dot-inventory or dot-player: duck-type it (a writer is `Variant`), or the script fails to parse where that addon is absent. [design](docs/design.md#optional-neighbours-are-duck-typed)
- `DotWeaponCatalogue.ids()` and `DotWeaponAmmo.pools()` are in text order: sort StringNames with `String(a) < String(b)`, never `sort()` (interning order, differs per process). The suite's id-order section is armed against it. [gdscript-hazards](../../docs/gdscript-hazards.md)
- Attachments apply to a deep copy of the definition, never the catalogue's row; both machines must share the attachment catalogue (the wire carries indices into it). [design](docs/design.md#attachments)
- The suite's extension-point section (`fixtures/lightning_rod.gd`) must keep passing. [design](docs/design.md#the-extension-point-is-tested)

## Consumers

game-arena and game-g2gfast use it directly. game-playground, game-zombie-zone, mg-deathrun, mg-prop-hunt, mg-smash-copter and mg-wipeout use it through zee-dot-weapons (zed-dot-weapons sits on top of zee). game-playground's prop tools (`DotPropTool` subclasses) are not weapons in this sense.
