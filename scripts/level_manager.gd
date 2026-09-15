extends Node2D

@onready var player_spawn = $PlayerSpawn

@export var player_scene: PackedScene

func _ready():
	# 1. Create an instance of the player
	var player = player_scene.instantiate() as CharacterBody2D
	
	# 2. Position the player at the last chunk spawn point reached, or this level's default
	player.global_position = _get_spawn_position()
	
	# 3. Add the player to the level
	add_child(player)

	var chunk_loader = get_node_or_null("ChunkLoader")
	if chunk_loader and chunk_loader.has_method("set_player"):
		chunk_loader.set_player(player)


func _get_spawn_position() -> Vector2:
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("get_spawn_position"):
		return game_manager.get_spawn_position(player_spawn.global_position)

	return player_spawn.global_position
