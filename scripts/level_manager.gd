extends Node2D

@onready var player_spawn = $PlayerSpawn

@export var player_scene: PackedScene

func _ready():
	# 1. Create an instance of the player
	var player = player_scene.instantiate() as CharacterBody2D
	
	# 2. Position the player at the Marker2D's location
	player.global_position = player_spawn.global_position
	
	# 3. Add the player to the level
	add_child(player)

	var chunk_loader = get_node_or_null("ChunkLoader")
	if chunk_loader and chunk_loader.has_method("set_player"):
		chunk_loader.set_player(player)
