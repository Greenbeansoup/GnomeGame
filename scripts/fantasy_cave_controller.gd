extends TileMapLayer

# Drag and drop your existing Light scene (.tscn) into this slot in the Inspector
@export var glow_worm_light: PackedScene
@export var mushroom_light: PackedScene

enum LightBias { TOP, BOTTOM }

func _ready() -> void:
	# Keep waiting frames until the engine actually reports data in the map
	while get_used_cells().is_empty():
		await get_tree().process_frame
	
	_spawn_lights_on_tiles()

func _spawn_lights_on_tiles() -> void:
	var lights_spawned := 0
	# Loop through every single painted cell on this tilemap layer
	for cell_pos in get_used_cells():
		var tile_data: TileData = get_cell_tile_data(cell_pos)
		if not tile_data:
			continue

		if tile_data.get_custom_data("glow_worm_top_tile") == true:
			if not glow_worm_light:
				push_warning("Please assign a glow_worm_light in the Inspector!")
			else:
				_create_light_at_position(cell_pos, glow_worm_light, LightBias.TOP)
				lights_spawned += 1

		if tile_data.get_custom_data("mushroom_bottom_tile") == true:
			if not mushroom_light:
				push_warning("Please assign a mushroom_light in the Inspector!")
			else:
				_create_light_at_position(cell_pos, mushroom_light, LightBias.BOTTOM)
				lights_spawned += 1

	print("_spawn_lights_on_tiles finished: ", get_used_cells().size(), " cells scanned, ", lights_spawned, " lights spawned")


func _create_light_at_position(cell_pos: Vector2i, light: PackedScene, bias: LightBias) -> void:
	# Instantiate your custom light resource or scene
	var new_light = light.instantiate()
	
	# Convert the grid coordinate (e.g., 5, 3) to local world pixels
	var local_pixel_pos = map_to_local(cell_pos)
	
	if bias == LightBias.TOP:
		local_pixel_pos.y -= 4
	if bias == LightBias.BOTTOM:
		local_pixel_pos.y += 3
	
	# Position the light and add it to the scene tree
	new_light.position = local_pixel_pos
	add_child(new_light)
