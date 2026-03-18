# Cursor handshake — Splode

Quick context for the next Cursor session (or any AI/developer) opening this project.

## What this is

- **Splode** — Godot 4 game: Cortex Command–style demolition, warehouse mission (destroy crate stack, then escape).
- **Main scene:** `scenes/missions/warehouse_mission.tscn` (script: `scripts/missions/warehouse_mission.gd`).
- **Version:** `project.godot` → `config/version` (currently 0.2.0). History: [CHANGELOG.md](CHANGELOG.md).

## Codebase map

| Area | Path | Notes |
|------|------|------|
| Mission / level | `scripts/missions/warehouse_mission.gd` | Spawns walls, pillars, crate, bombs; registers explosions; south wall = entrance + window. |
| Wall destruction | `scripts/destruction/wall_surface_damage.gd` | Cracking + material-based destruction (crumble, shatter, deform, splinter, **reinforced** with rebar). |
| Materials | `data/materials/*.json` + `scripts/materials/material_registry.gd` | Strength, destruction model, sounds. |
| Building sections | `data/building_sections/*.json` + `scripts/missions/building_section_registry.gd` | Thematic wall sections (not yet used for placement). |
| Gribblies | `data/gribblies/*.json` + `scripts/missions/gribbly_registry.gd` | Surface details (vents, pipes, panels); attach to sections. |
| Props | `scripts/props/*.gd` + `scenes/props/*.tscn` | e.g. `metal_door.gd`, `glass_window.gd`, `crate_stack.gd`, bombs. |
| Player | `scripts/player/player_controller.gd` | Movement, bomb equip/plant, health, squad. |

## Conventions

- **GDScript:** Use `StringName` for registry keys (`&"id"`). Prefix intentionally unused params with `_`.
- **Data:** JSON in `data/`; load via `*Registry` autoloads or direct load. Don’t hardcode paths that belong in data.
- **South wall:** Entrance = large warehouse door (3×3.5 m, scaled metal door); window to the right; cylindrical pillars in front. Geometry is in `warehouse_mission.tscn` + mission script.

## Docs to read first

1. [README.md](README.md) — run instructions, doc index.
2. [CHANGELOG.md](CHANGELOG.md) — what changed recently (e.g. reinforced concrete, pillars, gribblies, door).
3. [reference/README.md](reference/README.md) — art/damage reference images and usage.
4. [data/building_sections/README.md](data/building_sections/README.md) — section schema + `gribblies` array.
5. [data/gribblies/README.md](data/gribblies/README.md) — gribbly schema + `GribblyRegistry`.

## Handy commands

```bash
# From project root (splode/)
git status
git add -A && git commit -m "message"
git push origin main
```

## If the user says…

- **“Fix the door/window”** → Check `warehouse_mission.tscn` (SouthWall* nodes, GlassWindow1, MetalDoor) and positions/Z for wall face.
- **“Add a material / destruction type”** → `data/materials/*.json` + `wall_surface_damage.gd` `_get_destruction_params()` and optionally `_destroy_wall()` (e.g. rebar for `reinforced`).
- **“Building sections / gribblies”** → Data in `data/building_sections/`, `data/gribblies/`; registries in `scripts/missions/`. Placement from section data not yet implemented.
- **“Version / release”** → Bump `config/version` in `project.godot`, add entry to `CHANGELOG.md`, then commit and push.

---

*Last updated for v0.2.0; adjust as the project evolves.*
