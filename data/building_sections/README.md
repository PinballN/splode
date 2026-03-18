# Approved Building Sections

Curated, thematic wall and structure sections for procedural building. The AI or level builder selects from this folder to assemble structures that stay **interesting, logical, and on-theme** (e.g. brutalist).

## Schema (JSON)

Each file in this folder is one section. Required and optional fields:

```json
{
  "id": "unique_snake_case_id",
  "name": "Human-readable name",
  "theme": "brutalist",
  "tags": ["exterior", "window", "concrete"],
  "size": [2.0, 4.0, 0.6],
  "openings": [],
  "segments": [],
  "props": []
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| **id** | string | Unique id; filename should match (e.g. `brutalist_wall_window_2x2.json` → id `brutalist_wall_window_2x2`). |
| **name** | string | Display name for editors / AI. |
| **theme** | string | Visual theme: `brutalist`, `industrial`, `generic`, etc. Used to filter sections by style. |
| **tags** | array of string | Keywords for selection: `exterior`, `interior`, `window`, `door`, `concrete`, `metal`, etc. |
| **size** | [w, h, d] | Section bounding size in meters (width, height, depth). Local space. |
| **openings** | array | Cutouts (windows, doors). Each: `{ "type": "window"\|"door", "center": [x, y], "size": [w, h], "depth": 0.06, "scene": "res://..." }`. |
| **segments** | array | Wall geometry. Each: `{ "pos": [x, y, z], "size": [sx, sy, sz], "role": "sill"\|"lintel"\|"pillar"\|"plain", "material_id": "concrete" }`. Same format as facility layout templates. |
| **props** | array | Instanced scenes (door, window pane). Each: `{ "scene": "res://...", "pos": [x, y, z] }`. |
| **gribblies** | array | Optional. Surface-detail placements (vents, pipes, panels). Each: `{ "gribbly_id": "vent_round", "pos": [x, y, z], "rot_y": 0, "scale": [1,1,1] }`. Positions in section local space; use `rot_y` (degrees) for facing. Omitted fields use the gribbly’s defaults. |
| **connector_slots** | array | Optional. Edges that can attach to other sections: `["left", "right"]` etc. |
| **symmetry** | string | Optional. `"none"`, `"horizontal"`, `"vertical"` for placement/orientation hints. |

All positions and sizes are in **section local space**. When placing a section, the builder applies the section’s world transform (position + rotation) to these values.

## Selection rules (for AI / procedural system)

- Filter by **theme** to keep a consistent look (e.g. only `brutalist`).
- Use **tags** to pick “wall with window”, “wall with door”, “plain wall”, etc.
- Use **connector_slots** and **size** to align and chain sections without overlap.
- Prefer sections from this folder over ad-hoc geometry so layouts stay logical and thematic.
- For **Star Wars–style** variety: start with a **base structural section** (minimal segments, no or few props), then add **gribblies** in the section’s `gribblies` array, or pick gribblies at placement time from `GribblyRegistry` by theme/tag.

## Loading in code (BuildingSectionRegistry)

Use `BuildingSectionRegistry` to select sections by id, theme, or tag:

```gdscript
# One section by id
var section = BuildingSectionRegistry.get_section(&"brutalist_wall_window_2x2")

# All sections for a theme (e.g. for procedural brutalist structures)
var brutalist = BuildingSectionRegistry.get_sections_by_theme("brutalist")

# Sections that have a given tag (e.g. "window", "door")
var with_windows = BuildingSectionRegistry.get_sections_with_tag("window")
var with_door = BuildingSectionRegistry.get_sections_by_theme_and_tag("brutalist", "door")

# All section ids
var ids = BuildingSectionRegistry.get_all_section_ids()
```

The registry loads all `.json` files from `res://data/building_sections/` on first use. Instantiation (placing segments and props in the world from section data) can be implemented in the mission or a dedicated builder script using these dictionaries.

## Adding sections

1. Add a new `.json` file in `res://data/building_sections/`.
2. Use the schema above; keep `id` unique and match filename.
3. Use existing sections as reference for `segments` and `openings` so spawning code can stay consistent.
