@tool
extends Node2D
class_name WorldChunk

@export var terrain_layer_paths: Array[NodePath] = []


func get_terrain_at(world_position: Vector2) -> TileMapLayer:
	var closest_terrain: TileMapLayer
	var closest_distance_squared := INF

	for terrain_path in terrain_layer_paths:
		var terrain := get_node_or_null(terrain_path) as TileMapLayer
		if not terrain:
			continue

		var center_cell := terrain.local_to_map(terrain.to_local(world_position))
		for cell_x in range(center_cell.x - 2, center_cell.x + 3):
			for cell_y in range(center_cell.y - 2, center_cell.y + 3):
				var cell := Vector2i(cell_x, cell_y)
				if terrain.get_cell_source_id(cell) == -1:
					continue

				var cell_position := terrain.to_global(terrain.map_to_local(cell))
				var distance_squared := world_position.distance_squared_to(cell_position)
				if distance_squared < closest_distance_squared:
					closest_distance_squared = distance_squared
					closest_terrain = terrain

	return closest_terrain if closest_terrain else get_primary_terrain()


func get_primary_terrain() -> TileMapLayer:
	for terrain_path in terrain_layer_paths:
		var terrain := get_node_or_null(terrain_path) as TileMapLayer
		if terrain:
			return terrain

	return null
