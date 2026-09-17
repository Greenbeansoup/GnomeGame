extends Camera2D

@export var tween_speed: float = 0.0
@export var zoom_speed: float = 2.0

var tween: Tween
var following_player: Node2D = null
var active_zone: CameraZone = null
var overlapping_zones: Array[CameraZone] = []
var default_zoom: Vector2 = Vector2.ONE
# Lowest zoom scalar reached so far in the current ZOOM_OUT zone; zoom is never
# allowed to rise back above this while that zone stays active.
var zoom_out_floor: float = 1.0

func _ready() -> void:
	default_zoom = zoom
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

func _process(delta: float) -> void:
	if following_player and active_zone:
		global_position = _clamp_to_zone(following_player.global_position, active_zone)
		if active_zone.mode == CameraZone.Mode.ZOOM_OUT or active_zone.mode == CameraZone.Mode.ZOOM:
			_update_zoom(delta)
		else:
			zoom = zoom.move_toward(default_zoom, zoom_speed * delta)

func _on_zone_activated(zone: CameraZone, player: Node2D) -> void:
	overlapping_zones.erase(zone)
	overlapping_zones.append(zone)
	_activate_zone(zone, player)

func _activate_zone(zone: CameraZone, player: Node2D) -> void:
	if tween:
		tween.kill()

	active_zone = zone
	if zone.mode == CameraZone.Mode.ZOOM_OUT:
		zoom_out_floor = default_zoom.x

	if zone.mode == CameraZone.Mode.FOLLOW or zone.mode == CameraZone.Mode.ZOOM_OUT or zone.mode == CameraZone.Mode.ZOOM:
		following_player = player
		return

	following_player = null
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", _clamp_to_zone(zone.global_position, zone), tween_speed)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "zoom", default_zoom, tween_speed)\
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

func _update_zoom(delta: float) -> void:
	var target_scalar = _compute_fit_zoom(following_player.global_position, active_zone)
	if active_zone.mode == CameraZone.Mode.ZOOM_OUT:
		target_scalar = minf(target_scalar, zoom_out_floor)
		zoom_out_floor = target_scalar
	zoom = zoom.move_toward(Vector2(target_scalar, target_scalar), zoom_speed * delta)

# Returns the largest zoom scalar (<= default_zoom.x) that still keeps the camera's
# view inside the zone when centered on the player: near an edge this is default_zoom
# (no zoom out); near the zone's center it relaxes down to the zoom that fits the
# whole zone in view.
func _compute_fit_zoom(player_position: Vector2, zone: CameraZone) -> float:
	var viewport_size = get_viewport_rect().size
	var default_half_view = viewport_size / default_zoom.x / 2.0
	var zone_min = zone.global_position - zone.zone_size / 2.0
	var zone_max = zone.global_position + zone.zone_size / 2.0

	var dist_x = minf(player_position.x - zone_min.x, zone_max.x - player_position.x)
	var dist_y = minf(player_position.y - zone_min.y, zone_max.y - player_position.y)

	var upper_x = maxf(zone.zone_size.x / 2.0, default_half_view.x)
	var upper_y = maxf(zone.zone_size.y / 2.0, default_half_view.y)

	var desired_half_x = clampf(dist_x, default_half_view.x, upper_x)
	var desired_half_y = clampf(dist_y, default_half_view.y, upper_y)

	var zoom_x = viewport_size.x / (2.0 * desired_half_x)
	var zoom_y = viewport_size.y / (2.0 * desired_half_y)
	return minf(zoom_x, zoom_y)
