# Gribblies (surface details)

Small decorative/industrial props (vents, pipes, panels, conduits, hatches) that attach to **structural sections** to create varied, “lived-in” designs (e.g. Star Wars–style greebles).

## Schema (JSON)

Each file in this folder defines one gribbly type. Required and optional fields:

```json
{
  "id": "unique_snake_case_id",
  "name": "Human-readable name",
  "theme": "industrial",
  "tags": ["vent", "wall", "metal"],
  "scene": "res://scenes/gribblies/vent_round.tscn",
  "default_scale": [1.0, 1.0, 1.0],
  "anchor": "wall_surface"
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| **id** | string | Unique id; filename should match (e.g. `vent_round.json` → id `vent_round`). |
| **name** | string | Display name for editors / AI. |
| **theme** | string | Visual theme: `industrial`, `brutalist`, `sci_fi`, `generic`. Used to match section themes. |
| **tags** | array of string | Keywords: `vent`, `pipe`, `panel`, `conduit`, `hatch`, `wall`, `ceiling`, `metal`, etc. |
| **scene** | string | Scene path to instantiate (e.g. `res://scenes/gribblies/vent_round.tscn`). |
| **default_scale** | [sx, sy, sz] | Optional. Scale applied when not overridden by section placement. Default `[1,1,1]`. |
| **anchor** | string | Optional. Hint for snapping: `wall_surface`, `pillar`, `lintel`, `sill`, `generic`. Placement code can use this to align to segment normals. |

All positions/rotations for **where** a gribbly goes are defined on the **building section** in its `gribblies` array (see building_sections README).

## Loading in code (GribblyRegistry)

Use `GribblyRegistry` to select gribblies by id, theme, or tag:

```gdscript
# One gribbly by id
var g = GribblyRegistry.get_gribbly(&"vent_round")

# All gribblies for a theme
var industrial = GribblyRegistry.get_gribblies_by_theme("industrial")

# Gribblies with a given tag
var vents = GribblyRegistry.get_gribblies_with_tag("vent")

# All gribbly ids
var ids = GribblyRegistry.get_all_gribbly_ids()
```

## Workflow (Star Wars–style)

1. Pick a **base structural section** from the building section registry (e.g. plain wall, pillar bay).
2. Optionally pick **gribblies** by theme/tag from this registry.
3. Either use a section that already has `gribblies` placements in its JSON, or have the builder/placement code attach gribblies at runtime to slots/positions on the section.
4. Place section in world; spawn segments, props, then gribblies so the result stays thematic but varied.

## Adding gribblies

1. Add a new `.json` file in `res://data/gribblies/`.
2. Use the schema above; keep `id` unique and match filename.
3. Create or reference a scene under `res://scenes/gribblies/` (or elsewhere) for the visual. The scene should be a small prop that sits on a wall/surface (origin at attachment point, +Z or +X outward from wall as needed).
