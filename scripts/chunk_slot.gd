@tool
extends Node2D
class_name ChunkSlot

signal chunk_loaded(chunk: Node2D)
signal chunk_unloaded

@export var chunk_scene: PackedScene:
	set(value):
		if chunk_scene and chunk_scene.changed.is_connected(_on_chunk_scene_changed):
			chunk_scene.changed.disconnect(_on_chunk_scene_changed)
		chunk_scene = value
		if chunk_scene and not chunk_scene.changed.is_connected(_on_chunk_scene_changed):
			chunk_scene.changed.connect(_on_chunk_scene_changed)
		if Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_refresh_editor_preview")
@export var active_rect := Rect2(-288.0, -162.0, 576.0, 324.0):
	set(value):
		active_rect = value
		queue_redraw()
@export_range(0.0, 4096.0, 1.0) var preload_margin := 256.0:
	set(value):
		preload_margin = value
		queue_redraw()
@export_range(0.0, 4096.0, 1.0) var unload_margin := 512.0:
	set(value):
		unload_margin = value
		queue_redraw()
@export_category("Editor Preview")
@export var preview_in_editor := true:
	set(value):
		preview_in_editor = value
		if Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_refresh_editor_preview")

var chunk: Node2D
var editor_preview: Node2D


func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_preview")
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	draw_rect(active_rect.grow(preload_margin), Color(0.2, 0.65, 1.0, 0.15), true)
	draw_rect(active_rect, Color(0.2, 0.65, 1.0, 0.9), false, 2.0)


func _on_chunk_scene_changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		call_deferred("_refresh_editor_preview")


func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

	if is_instance_valid(editor_preview):
		remove_child(editor_preview)
		editor_preview.queue_free()
		editor_preview = null

	if not preview_in_editor or not chunk_scene:
		return

	var instance := chunk_scene.instantiate()
	if not instance is Node2D:
		instance.free()
		return

	editor_preview = instance as Node2D
	editor_preview.name = "ChunkPreview"
	editor_preview.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(editor_preview)


func get_world_rect(margin: float = 0.0) -> Rect2:
	return Rect2(global_position + active_rect.position, active_rect.size).grow(margin)


func is_loaded() -> bool:
	return is_instance_valid(chunk)


func load_chunk() -> Node2D:
	if is_loaded() or not chunk_scene:
		return chunk

	var instance := chunk_scene.instantiate()
	if not instance is Node2D or not instance.has_method("get_primary_terrain"):
		push_error("Chunk scene '%s' must use world_chunk.gd as its root script." % chunk_scene.resource_path)
		instance.free()
		return null

	chunk = instance as Node2D
	add_child(chunk)
	chunk_loaded.emit(chunk)
	return chunk


func unload_chunk() -> void:
	if not is_loaded():
		return

	chunk.queue_free()
	chunk = null
	chunk_unloaded.emit()