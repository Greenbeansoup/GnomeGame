# Gnome Platformer

## Local setup

This project commits Aseprite Wizard under `addons/` so teammates can clone the repo with the importer plugin available. Beehave is intentionally not committed; the export workflow pulls a known Beehave version from GitHub during CI builds.

### Aseprite imports

Some sprites are imported from `.aseprite` source files through Aseprite Wizard. Godot must be able to run the Aseprite executable when those assets are imported or reimported.

On Windows, Aseprite Wizard defaults to:

```text
C:\Steam\steamapps\common\Aseprite\aseprite.exe
```

If Aseprite is installed somewhere else, set the path in Godot:

```text
Editor > Editor Settings > Aseprite > General > Command Path
```

The project also enables Aseprite Wizard bake files. When an artist with Aseprite reimports `.aseprite` assets, the generated `.*.ase_bake.res` files beside those sources should be committed so teammates without Aseprite can still use the already-generated imports.

### Beehave

Beehave is vendored during GitHub Actions exports from `bitbrain/beehave` tag `v2.9.3`. For local development, install Beehave into `addons/beehave` yourself if you need to edit or run behavior-tree scenes locally. The folder is ignored so local installs do not get committed accidentally.

The Beehave autoloads in `project.godot` intentionally use `res://addons/beehave/...` paths instead of `uid://...` references. Local Beehave installs can generate different `.uid` files on different machines, so do not commit `project.godot` changes that only rewrite those Beehave autoloads back to `uid://` values.

## World chunks

The main world keeps the player and camera alive while `ChunkLoader` streams authored chunk scenes in and out. Unloading a chunk also frees the lights generated beneath its tilemaps.

To create a chunk:

1. Create a `Node2D` scene and attach `scripts/world_chunk.gd` to its root.
2. Add terrain, camera zones, enemies, hazards, lighting, and local environment art beneath that root.
3. Add each terrain layer the player can dig through to the root's `terrain_layer_paths`. Put the primary layer first.
4. Add a `Node2D` beneath `Game/ChunkLoader`, attach `scripts/chunk_slot.gd`, and assign the chunk scene.
5. Position the slot where the chunk belongs and set `active_rect` to the chunk's playable world area. The blue editor rectangle previews it; `preload_margin` loads ahead of the player and `unload_margin` prevents rapid unload/reload at an edge.

Chunk roots must remain at local `(0, 0)` inside their scenes. Use the `ChunkSlot` position to place the complete chunk in the world. Neighboring slots should have enough preload overlap that terrain and lights are ready before the player crosses between them.

Assigned chunk scenes are rendered as editor-only previews beneath their slots, so the assembled world remains visible in `game.tscn`. Select a slot and enable `Editor Preview > Preview In Editor` if its preview has been disabled. The generated `ChunkPreview` child has no scene owner, so it is not saved into the world scene and is replaced by the streamed runtime instance when the game runs. Edit a chunk's contents in its own scene, then use `game.tscn` to position it alongside neighboring chunks and tune its streaming bounds.