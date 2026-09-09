@tool
extends Area2D
class_name CameraZone

# World-space size of one room: the 1152x648 viewport divided by the Camera2D's 2x zoom.
# Only used for the editor snap-to-grid convenience below; room activation itself is
# detected physically via Area2D overlap, so it works regardless of world-space alignment.
const ROOM_WIDTH: float = 576.0
const ROOM_HEIGHT: float = 324.0

# STATIC: camera snaps once to this zone's position and stays put.
# FOLLOW: camera tracks the player continuously until they leave this zone.
enum Mode { STATIC, FOLLOW }
@export var mode: Mode = Mode.STATIC

# Size of the detection area, editable per-instance so reused zones can be made
# bigger than a single room (e.g. for FOLLOW mode) without touching the shared scene.
@export var zone_size: Vector2 = Vector2(ROOM_WIDTH, ROOM_HEIGHT):
	set(value):
		zone_size = value
		_apply_zone_size()

signal zone_activated(zone: CameraZone, player: Node2D)
signal zone_exited(zone: CameraZone, player: Node2D)

@export_subgroup("Automation Tools")
@export var snap_to_grid_now: bool = false:
	set(value):
		_snap_to_nearest_grid_slot()

@export_storage var grid_coords: Vector2i = Vector2i.ZERO

func _ready() -> void:
	_apply_zone_size()
	if not Engine.is_editor_hint():
		add_to_group("camera_markers")
		_calculate_grid_coords()
		area_entered.connect(_on_area_entered)
		area_exited.connect(_on_area_exited)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_calculate_grid_coords()

func _apply_zone_size() -> void:
	if not is_inside_tree():
		return
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not shape_node:
		return
	# Duplicate so resizing one instance doesn't resize the shape resource shared by others.
	var rect: RectangleShape2D = (shape_node.shape as RectangleShape2D).duplicate() if shape_node.shape is RectangleShape2D else RectangleShape2D.new()
	rect.size = zone_size
	shape_node.shape = rect

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_room_detector"):
		zone_activated.emit(self, area.get_parent())

func _on_area_exited(area: Area2D) -> void:
	if area.is_in_group("player_room_detector"):
		zone_exited.emit(self, area.get_parent())

func _calculate_grid_coords() -> void:
	# For editor bookkeeping/labeling only; not used to decide when the camera moves.
	var current_x := int(floor(global_position.x / ROOM_WIDTH))
	var current_y := int(floor(global_position.y / ROOM_HEIGHT))
	grid_coords = Vector2i(current_x, current_y)


func _snap_to_nearest_grid_slot() -> void:
	# This perfectly centers the zone node right in the middle of its grid coordinate box
	var current_x = floor(global_position.x / ROOM_WIDTH)
	var current_y = floor(global_position.y / ROOM_HEIGHT)
	grid_coords = Vector2i(current_x, current_y)
	
	global_position = Vector2(
		(grid_coords.x * ROOM_WIDTH) + (ROOM_WIDTH / 2.0),
		(grid_coords.y * ROOM_HEIGHT) + (ROOM_HEIGHT / 2.0)
	)
