# Weapon spawners

A generic "something appears here, is taken, and comes back" layer: weapon spawners on a map, ammo and health pickups, a trader's shelf. It lives in `addons/dot_weapon/spawner/` because it draws from the weapon catalogue's ids and tags; nothing in it names a weapon, an entry id is any string the game understands and `kind` says what the game does with it. It places nothing in the world: the server's `DotWeaponSpawner` emits events, the game makes and removes the pickup.

## Pieces

| Class | Role |
| --- | --- |
| `DotWeaponSpawnSite` | plain data for one place: `id`, `position`, `rotation_y`, `pool`, `item` (fixed), `filter`, `respawn_seconds`, `respawn_jitter`, `initial_delay`, `max_alive`, `one_shot`, `lifetime_seconds`, `group`, `kind`, `enabled`, `data` |
| `DotWeaponSpawnPoint` | the `Node3D` marker a mapper places (exports of the same fields; `collect(root)`) |
| `DotWeaponSpawnPool` | weighted entries `{id, kind, weight, tags, data}`; `candidates(filter)`, `pick(filter, unit)`; built from config with an optional `catalogue:` block that adds every `DotWeaponDef` whose tags match |
| `DotWeaponSpawnerConfig` | the layered file, `MAP_KEYS` (scalars for dot-map), `get_setting`/`set_setting` |
| `DotWeaponSpawner` | server: `load_map`, `add_entities`, `begin_round`, `tick`, `take`, `roll`, `snapshot`; signals `changed(event)`, `spawned`, `taken` |
| `DotWeaponSpawnView` | client mirror: `apply(event)`, `apply_snapshot(snap)`; signals `appeared`, `vanished` |

## Server use

```gdscript
var spawner := DotWeaponSpawner.new()
spawner.config.game = "game-x"          # reads cfg/game/game-x/dot_weapon/spawner.yml
spawner.config.defs = my_weapon_defs    # for pools with a catalogue: block
spawner.config.load_files()
spawner.load_map(map_id, DotWeaponSpawnPoint.collect(map_root))   # and/or spawner.add_entities(entities)
spawner.changed.connect(send_event_to_clients)   # [&"spawn", inst, site, item, kind, pos, rot_y, data] / [&"take", inst, taker]
spawner.spawned.connect(make_pickup)             # (instance, site, item, kind, at)
spawner.begin_round(now, round_number)           # every round: new seeded draw
spawner.tick(now)                                # every server tick, the game clock
# the pickup was used:
var r := spawner.take(instance, player_id)       # fails if already gone; r.value = {item, kind, site, data}
```

`take` is the only way a pickup is consumed, and it fails for an instance already taken, so two players pressing use in one tick cannot both receive it. `roll(site, n)` draws without spawning: a trader rolls its stock with `n = 0..k`.

## Client use

Send each `changed` event over the game's channel and call `view.apply(event)`; send `spawner.snapshot()` to a joining client and call `view.apply_snapshot(snap)`. Draw from `appeared` (instance, site, item, kind, at, rotation_y, data) and `vanished`. `view.waiting[site]` is seconds until the next item as of the last snapshot, for a countdown.

## Config

`spawner.yml`, layered by dot-core's `DotAddonConfig` (`cfg/addons/dot_weapon/`, `cfg/game/<game>/dot_weapon/`, then `cfg/server/...` for the operator), merged key by key.

```yaml
default_pool: guns
pools:
  guns:
    kind: weapon
    catalogue:
      tags_any: [primary, sidearm]
      tags_none: [heavy]
      weight: 1
      weights:
        shotgun: 3
    entries:
      - id: medkit
        kind: pickup
        weight: 1
        tags: [heal]
        data:
          price: 0
sites:                      # by site id, over the marker's own fields
  armoury:
    pool: guns
    respawn: 45
    max: 2
    group: guns
groups:
  guns: 6                   # at most six alive across sites of the group
classes:                    # entity classnames (globs) a converter maps to spawners
  weapon_spawn_*:
    pool: guns
maps:                       # per-map blocks, same keys; id or glob, the more literal characters win
  zz_lot:
    sites:
      armoury:
        respawn: 20
```

The parser (`DotYaml`) has no inline mappings (`{a: 1}` is an error); lists of scalars may be inline (`[a, b]`). A site's fields come from, weakest first: the marker or entity, `sites:` in the file, the matching `maps:` blocks. Site keys accept `respawn`/`max`/`lifetime` as short names. A filter is `tags_any`, `tags_all`, `tags_none`, `ids` (lists or `"a, b"`); weight 0 removes an entry.

### Scalars through dot-map's per-map files

`DotWeaponSpawnerConfig.MAP_KEYS` is a schema for `DotMapConfig`: `spawner_enabled`, `spawner_respawn_scale`, `spawner_max_scale`, `spawner_seed`, `spawner_pool`. A game adds them to `_map_config_keys()` and routes them in `_map_config_get/_set` to `config.get_setting/set_setting`; then `cfg/game/<game>/dot_map/map/<name>.yml` (and the operator's copy, and `--dot-map.map.spawner_respawn_scale=2`) sets them per map or per map glob, and dot-map restores them on the next map. Apply them before `begin_round`.

## Randomness

A draw is `stream(seed, site id, round).unit_at(n)` with n the site's own draw count (the jitter uses the odd indices), so a given seed, map and round gives the same items whatever the order sites tick in, and a new round gives new ones. Seed 0 means derived from the map id; `spawner_seed` fixes it.

## Map entities

`add_entities` takes `{classname, origin (Vector3 or [x,y,z]), angle (degrees), props}`. A classname matching a `classes:` glob (or `dot_weapon_spawn`) becomes a site; the class mapping is its defaults and `props` (string values are coerced) come over that. A converter maps a source's weapon entities to such a class and the config decides what they give.

## Trader and map pickups

The file's `game:` mapping is the game's own block (prices, rules); `spawner.game_block()` returns it merged for the map.

Same machinery: a trader is a site with `pool: stock`, entries carrying `data: {price: 50}` (it rides on the event) and `max_alive` for shelf slots, or `roll()` for a fixed shelf; a fixed map pickup is a site with `item: medkit` and a respawn time (or `one_shot`).

## Channels: where an item is offered

A pool may carry `channel: shop` (any label). Set `config.weigher = func(channel, id, weight) -> float` and every entry of every pool is re-weighed through it as the pools are built (0 removes the entry), so a game keeps "never in the shop" or per-weapon odds in its own config without a pool per rule.

## Limits

Ammo for a weapon found is the game's. The spawner does not know a pickup was moved or destroyed other than through `take` (call it, or let `lifetime_seconds` expire it).


## Reference moved from the class docs

### DotWeaponSpawner: usage and determinism

It places nothing in the world: it says "item X now lies at P" through [signal changed] and the game makes the pickup (a loot entry, a node, a trader's shelf). When the game's pickup is used it calls [method take], which frees the slot and starts the timer. Time is whatever clock the game passes to [method tick], so a test can drive it.

```
var spawner := DotWeaponSpawner.new()
spawner.config.game = "game-x"          # the cfg/game/<game>/dot_weapon/spawner.yml tier
spawner.config.load_files()
spawner.load_map(map_id, DotWeaponSpawnPoint.collect(map_root))   # or add_entities(doc_entities)
spawner.changed.connect(func(ev: Array) -> void: send_to_clients(ev))
spawner.begin_round(now, round_number)  # then spawner.tick(now) every server tick
# on use:  var r := spawner.take(instance, player_id)   # r.value = {item, kind, site, data}
```

[b]Determinism.[/b] A draw is `stream(seed, site, round).unit_at(n)`, n the site's own draw count, so the same seed, map and round give the same items whatever order sites tick in; a new round changes them.

### DotWeaponSpawnerConfig: layers and format

[b]Two kinds of setting.[/b] The structure (pools, sites, groups) is `spawner.yml` in each `dot-weapon` tier of [DotAddonConfig]: `cfg/addons/dot_weapon/`, `cfg/game/<game>/dot_weapon/`, then the operator's `cfg/server/...` copies, merged weakest first. A top-level `maps:` mapping holds per-map blocks (same keys) under a map id or a glob (`zz_*`, case-insensitive); the more literal characters win. The scalars in [method map_keys] go through dot-map's per-map files instead (`dot_map/map/<name>.yml`), which is where a game's [code]DotGameModule._map_config_get/_set[/code] reach them, so a map can switch spawners off or halve a timer without a block here.

```
pools:
  wall_guns:
    kind: weapon
    catalogue:
      tags_any: [primary]
      weight: 1
sites:                  # defaults by spawner id, over what the marker says
  armoury:
    pool: wall_guns
    respawn: 45
game:                   # free-form block for the game
  shop:
    prices:
      primary: 500
```

DotYaml has no inline mappings: write every mapping in block style (lists of scalars may stay inline).
