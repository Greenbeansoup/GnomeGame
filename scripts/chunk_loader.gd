extends Node2D
class_name ChunkLoader

@export var player_path: NodePath

var player: CharacterBody2D
var active_slot: Node2D


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
