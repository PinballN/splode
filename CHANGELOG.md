# Changelog

All notable changes to Splode are documented here. Version format: [SemVer](https://semver.org/).

## [0.2.1] – 2026-03-18

### Added
- **Crate ignition sparks**: `CrateStack` now bursts visible sparks and spawns a few lingering floor embers that fade out over a random lifetime.
- **Debris push**: player bumping into wall rubble now imparts impulse so chunks slide out of the way.

### Changed
- **Debris behavior**: persistent rubble collision stays enabled; rubble piles cluster near impact point; rebar “skeleton” mixes upright rods with horizontal strands.
- **Visuals/lighting**: overhead warehouse lighting added and tuned; interior floor separated from outside ground with distinct materials and sizing.
- **Metal door**: lighter grey material so the blown-off door reads better.

## [0.2.0] – 2025-03-17

### Added
- **Reinforced concrete** material and destruction: concrete crumbles, rebar skeleton (rust-colored rods) remains when destroyed.
- **Entrance pillar row**: cylindrical reinforced-concrete bollards outside south entrance to deter vehicles.
- **Gribblies system**: `data/gribblies/` schema and `GribblyRegistry` for attaching surface details (vents, pipes, panels) to structural sections; building sections can include a `gribblies` array.
- **Building sections**: industrial base sections and greebled example; optional `gribblies` on sections.
- **Reference image library**: `reference/` with reinforced concrete pillar damage and window-in-wall (stone frame) references; README updated.

### Changed
- **South wall / entrance**: Large warehouse-style metal door (3 m × 3.5 m) in entrance gap; door pillars full height (3.5 m), lintel widened; window and door aligned on wall front face (Z).
- **Entrance pillars**: Switched from box to **cylinder** mesh and collision; `WallSurfaceDamage` supports `CylinderMesh` for correct destruction bounds.
- **Project version**: Set `config/version="0.2.0"` in `project.godot`.

### Fixed
- GDScript: unused parameters in `_spawn_rebar_skeleton` prefixed with underscore; confusable local declarations in `_attach_exterior_walls_damageable` resolved (single declaration of strength/colors per iteration).

---

## [0.1.0] – (earlier)

- Initial warehouse mission, wall damage (crumble/shatter/deform/splinter), materials, bombs, player, HUD, fog of war, roof cutaway, building section registry, facility layouts.
