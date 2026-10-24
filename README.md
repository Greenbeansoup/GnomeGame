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

## Enemy pursuit

Instance `scenes/pursuit_behavior.tscn` beneath a `CharacterBody2D` enemy. The component owns its Beehave tree and the shared flow: idle, detection, pursuit, active idle (watching), then idle. Losing sight preserves the last known position; reaching it or getting stuck starts the watch timeout. A target seen while watching resumes pursuit immediately.

Assign `detect_area` in the Inspector. Set its collision mask to your target's layer and give the target the `player` group (or change `target_group`). Idle detection is directional. Optionally assign `aggro_sight` for a separate pursuit/watch area, `line_of_sight` for occlusion checks in those states, and `body_shape` for the rear detection margin. Author the aggro area facing left; the component mirrors it with facing. The ray's mask must include targets and blocking terrain.

Assign an optional `animation_player` and map the animation names and playback speeds. Missing/empty names are skipped, so enemies do not need every sprinter animation. Spotted and windup animations must be non-looping: they finish before movement begins. Detection, pursuit, and idle animations may loop. Use `flip_detection` from animation tracks when an active-idle animation looks behind the enemy.

The component sets horizontal velocity but does not apply gravity or call `move_and_slide()`. The enemy owns physics. For deterministic ordering, disable `automatic_update` and call `pursuit.update(delta)` before `move_and_slide()` from the enemy's physics callback. Otherwise, the component updates itself each physics frame.

Tune pursuit range, speed, stop/resume distances, watch duration (`forget_time`), and stuck timeout/progress distance in the Inspector. Connect `state_changed`, `target_changed`, `facing_changed`, and `pursuit_changed` for enemy-specific visuals, sound, or music. Set `enabled = false` to suspend decision-making during knockback; use `stop()` on death to clear the target and halt pursuit permanently.

Optional enemy hooks:

- `chase_position(destination: Vector2) -> bool`: override horizontal movement and return whether the enemy is holding at its destination. The sprinter uses this for its body-width stopping margin and facing rules. The component's speed/stop settings apply to default movement; custom movement owns its own tuning.
- `play_animation(name: String, speed: float)`: override animation playback, for example to track attack state alongside the AnimationPlayer.
- `face_player(target: Node2D)`: face a visible target before preparation animations.
- `tick_pursuit_combat() -> bool`: return `true` while combat takes priority over pursuit. The enemy owns attack animation completion and cooldowns.

The sprinter is a working integration: it retains hammer combat, vaulting, knockback, and chunk exports while its child component owns sensing and pursuit state. Its `automatic_update` is disabled so pushes and death cannot accidentally tick its AI.

Run the focused checks with your Godot executable:

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script tests/test_pursuit.gd
godot --headless --path . --script tests/test_vault.gd
```

The editor scan registers new global script classes on a fresh checkout. Beehave may log debugger-message errors during standalone headless tests because no editor debugger is attached.

## Enemy vaulting

Instance `scenes/vault_behavior.tscn` beneath any `CharacterBody2D` enemy and assign its `body_shape`. The parent is used as the actor by default. Call `vault.update()` after choosing horizontal velocity and applying gravity, but before `move_and_slide()`. No pursuit component is required: vaulting follows the actor's horizontal velocity.

The component probes ahead at foot height and at `obstacle_height`, jumping only when the lower ray is blocked and the upper ray is clear. Tune `probe_distance`, `jump_velocity`, `retry_jump_velocity`, and `max_attempts` on the component. Attempts reset after forward progress or stopping. It does not jump again in midair, and stops retrying after the configured attempt limit until progress or a reset. Call `reset()` when interrupting movement, or set `enabled = false` to disable vaulting.

Both the sprinter and explode gnome use this component. The sprinter's existing root vault tuning exports are preserved and forwarded to its child. Knockback and death paths skip vault updates.

## World chunks

The main world keeps the player and camera alive while `ChunkLoader` streams authored chunk scenes in and out. Unloading a chunk also frees the lights generated beneath its tilemaps.

To create a chunk:

1. Create a `Node2D` scene and attach `scripts/world_chunk.gd` to its root.
2. Add terrain, camera zones, enemies, hazards, lighting, and local environment art beneath that root.
3. Add each terrain layer the player can dig through to the root's `terrain_layer_paths`. Put the primary layer first.
4. Add a `Node2D` beneath `Game/ChunkLoader`, attach `scripts/chunk_slot.gd`, and assign the chunk scene.
5. Position the slot where the chunk belongs and set `active_rect` to the chunk's playable world area. The blue editor rectangle previews it; `preload_margin` (blue) loads ahead of the player and `unload_margin` (orange) prevents rapid unload/reload at an edge. Both margins are `Vector2`s, so the x and y axes can be tuned independently.

Chunk roots must remain at local `(0, 0)` inside their scenes. Use the `ChunkSlot` position to place the complete chunk in the world. Neighboring slots should have enough preload overlap that terrain and lights are ready before the player crosses between them.

Assigned chunk scenes are rendered as editor-only previews beneath their slots, so the assembled world remains visible in `game.tscn`. Select a slot and enable `Editor Preview > Preview In Editor` if its preview has been disabled. The generated `ChunkPreview` child has no scene owner, so it is not saved into the world scene and is replaced by the streamed runtime instance when the game runs. Edit a chunk's contents in its own scene, then use `game.tscn` to position it alongside neighboring chunks and tune its streaming bounds.