extends Camera2D

@export var tween_speed: float = 0.0

var tween: Tween
var following_player: Node2D = null
var active_zone: CameraZone = null
var overlapping_zones: Array[CameraZone] = []

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	# Defer so every initial CameraZone has entered the tree.
	call_deferred("_connect_zones")

func _connect_zones() -> void:
	for zone in get_tree().get_nodes_in_group("camera_zones"):
		if zone is CameraZone:
			_connect_zone(zone)

func _on_node_added(node: Node) -> void:
	if node is CameraZone:
		_connect_zone(node)

func _connect_zone(zone: CameraZone) -> void:
	if not zone.zone_activated.is_connected(_on_zone_activated):
		zone.zone_activated.connect(_on_zone_activated)
	if not zone.zone_exited.is_connected(_on_zone_exited):
		zone.zone_exited.connect(_on_zone_exited)

func _process(_delta: float) -> void:
	if following_player and active_zone:
		global_position = _clamp_to_zone(following_player.global_position, active_zone)

func _on_zone_activated(zone: CameraZone, player: Node2D) -> void:
	overlapping_zones.erase(zone)
	overlapping_zones.append(zone)
	_activate_zone(zone, player)

func _activate_zone(zone: CameraZone, player: Node2D) -> void:
	if tween:
		tween.kill()

	active_zone = zone
	if zone.mode == CameraZone.Mode.FOLLOW:
		following_player = player
		return

	following_player = null
	tween = create_tween()
	tween.tween_property(self, "global_position", _clamp_to_zone(zone.global_position, zone), tween_speed)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)

func _on_zone_exited(zone: CameraZone, player: Node2D) -> void:
	overlapping_zones.erase(zone)

	if active_zone != zone:
		return

	if overlapping_zones.is_empty():
		active_zone = null
		following_player = null
	else:
		_activate_zone(overlapping_zones.back(), player)

# Keeps the camera's visible rect fully inside the zone; axes narrower than the view
# (e.g. a corridor one camera-width wide) are simply pinned to the zone's center.
func _clamp_to_zone(target_position: Vector2, zone: CameraZone) -> Vector2:
	var half_view = get_viewport_rect().size / zoom / 2.0
	var zone_min = zone.global_position - zone.zone_size / 2.0
	var zone_max = zone.global_position + zone.zone_size / 2.0
	var clamped = target_position

	if zone.zone_size.x <= half_view.x * 2.0:
		clamped.x = zone.global_position.x
	else:
		clamped.x = clampf(target_position.x, zone_min.x + half_view.x, zone_max.x - half_view.x)

	if zone.zone_size.y <= half_view.y * 2.0:
		clamped.y = zone.global_position.y
	else:
		clamped.y = clampf(target_position.y, zone_min.y + half_view.y, zone_max.y - half_view.y)

	return clamped
