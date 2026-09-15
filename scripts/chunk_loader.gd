extends Node2D
class_name ChunkLoader

@export var player_path: NodePath

var player: CharacterBody2D
var active_slot: Node2D


func _ready() -> void:
	add_to_group("chunk_loader")
	for child in get_children():
		if child.has_signal("player_entered"):
			child.player_entered.connect(_on_slot_player_entered.bind(child))


# Resets any currently streamed-in chunks (hazards, pickups, etc.) without touching
# the rest of the level tree, e.g. camera and chunk loader stay put across a respawn.
func reload_active_chunks() -> void:
	for child in get_children():
		if not child.has_method("load_chunk") or not child.is_loaded():
			continue
		child.unload_chunk()
		child.load_chunk()


func set_player(value: CharacterBody2D) -> void:
	player = value
	_update_loaded_chunks()
	_update_player_terrain()


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		player = _find_player()
		if not player:
			return

	_update_loaded_chunks()
	_update_player_terrain()


func _find_player() -> CharacterBody2D:
	if not player_path.is_empty():
		var configured_player := get_node_or_null(player_path) as CharacterBody2D
		if configured_player:
			return configured_player

	return get_tree().get_first_node_in_group("player") as CharacterBody2D


func _update_loaded_chunks() -> void:
	for child in get_children():
		if not child.has_method("load_chunk"):
			continue
		var slot = child

		if slot.is_loaded():
			if not slot.get_world_rect(slot.unload_margin).has_point(player.global_position):
				if slot == active_slot and player.get("is_earthwalking") == true:
					continue
				slot.unload_chunk()
		else:
			if slot.get_world_rect(slot.preload_margin).has_point(player.global_position):
				slot.load_chunk()


func _update_player_terrain() -> void:
	var containing_slot: Node2D
	var loaded_terrains: Array[TileMapLayer] = []
	for child in get_children():
		if not child.has_method("load_chunk"):
			continue
		var slot = child
		if not slot.is_loaded():
			continue

		for terrain in slot.chunk.get_terrain_layers():
			loaded_terrains.append(terrain)

		if not containing_slot and slot.get_world_rect().has_point(player.global_position):
			containing_slot = slot

	active_slot = containing_slot
	var terrain: TileMapLayer
	if active_slot and active_slot.chunk:
		terrain = active_slot.chunk.get_terrain_at(player.global_position)
	if player.has_method("set_terrain_layers"):
		player.set_terrain_layers(loaded_terrains, terrain)
		return
	if player.get("tile_map_layer") != terrain:
		player.set("tile_map_layer", terrain)


# Fired by a slot's Area2D instead of polling every frame; if the chunk hasn't finished
# loading yet, retry once it does rather than silently missing this entry.
func _on_slot_player_entered(_body: Node, slot: Node2D) -> void:
	if _register_spawn_point(slot):
		return
	slot.chunk_loaded.connect(_on_slot_chunk_loaded.bind(slot), CONNECT_ONE_SHOT)


func _on_slot_chunk_loaded(_chunk: Node2D, slot: Node2D) -> void:
	_register_spawn_point(slot)


func _register_spawn_point(slot: Node2D) -> bool:
	var chunk := slot.chunk as WorldChunk
	if not chunk:
		return false

	var spawn := chunk.get_player_spawn()
	if not spawn:
		return true

	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("set_last_spawn"):
		game_manager.set_last_spawn(spawn.global_position)
	return true
