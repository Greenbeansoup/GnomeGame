@tool
extends Node2D
class_name ChunkSlot

signal chunk_loaded(chunk: Node2D)
signal chunk_unloaded
signal player_entered(body: Node)

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
		_update_entry_area_shape()
# Per-axis margins let a chunk preload/unload sooner along one axis than the other
# (e.g. a tall vertical shaft vs. a wide horizontal corridor).
@export var preload_margin := Vector2(256.0, 256.0):
	set(value):
		preload_margin = value.max(Vector2.ZERO)
		queue_redraw()
@export var unload_margin := Vector2(512.0, 512.0):
	set(value):
		unload_margin = value.max(Vector2.ZERO)
		queue_redraw()
@export_category("Editor Preview")
@export var preview_in_editor := true:
	set(value):
		preview_in_editor = value
		if Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_refresh_editor_preview")
@export var show_margin_gizmos := true:
	set(value):
		show_margin_gizmos = value
		queue_redraw()

var chunk: Node2D
var editor_preview: Node2D
var _entry_area: Area2D


func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_preview")
		queue_redraw()
	else:
		_setup_entry_area()


# Detects the player crossing into this slot's bounds via a physics signal instead of a
# per-frame position check across every slot.
func _setup_entry_area() -> void:
	_entry_area = Area2D.new()
	_entry_area.monitorable = false
	add_child(_entry_area)

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = RectangleShape2D.new()
	_entry_area.add_child(collision_shape)
	_update_entry_area_shape()

	_entry_area.body_entered.connect(_on_entry_area_body_entered)


func _update_entry_area_shape() -> void:
	if not is_instance_valid(_entry_area):
		return

	var collision_shape := _entry_area.get_child(0) as CollisionShape2D
	collision_shape.shape.size = active_rect.size
	collision_shape.position = active_rect.position + active_rect.size / 2.0


func _on_entry_area_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_entered.emit(body)


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_margin_gizmos:
		return

	draw_rect(_grow_rect(active_rect, unload_margin), Color(1.0, 0.55, 0.15, 0.12), true)
	draw_rect(_grow_rect(active_rect, preload_margin), Color(0.2, 0.65, 1.0, 0.15), true)
	draw_rect(active_rect, Color(0.2, 0.65, 1.0, 0.9), false, 2.0)


func _grow_rect(rect: Rect2, margin: Vector2) -> Rect2:
	return rect.grow_individual(margin.x, margin.y, margin.x, margin.y)


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


func get_world_rect(margin: Vector2 = Vector2.ZERO) -> Rect2:
	return _grow_rect(Rect2(global_position + active_rect.position, active_rect.size), margin)


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