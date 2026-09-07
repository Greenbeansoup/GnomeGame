extends CharacterBody2D

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var collision_shape_2d = $CollisionShape2D
@export var tile_map_layer: TileMapLayer

const SPEED = 130.0
const SPRINT_SPEED = SPEED * 1.5
const AIR_DECELERATION = SPEED * 0.1
const AIR_ACCELERATION = SPEED * 0.2
const JUMP_VELOCITY = -250.0
# 14x14 earthwalk footprint centered at the sprite's local position of (0, -7).
const EARTHWALK_SPRITE_MIN = Vector2(-7.0, -14.0)
const EARTHWALK_SPRITE_MAX = Vector2(7.0, 0.0)
# Keeps the footprint inside the cell; an exact maximum edge maps to the next TileMap cell.
const EARTHWALK_BOUNDARY_INSET = 0.01
# The exported animation frames use a 64x42 canvas.
const GNOME_FRAME_HEIGHT = 42.0
# A rotated frame is 42px wide, so move it fully out on the horizontal axis; nudged down
# a few px from the full frame height so the dig-out reveal lines up with the earth tile.
const DIG_OUT_SIDE_VISUAL_OFFSET = GNOME_FRAME_HEIGHT - 2.0
const DIG_OUT_SIDE_VERTICAL_OFFSET = -7.0
# A flipped frame needs to move down its full height to sit beneath the tile; nudged down
# a few px from the full frame height so the dig-out reveal lines up with the earth tile.
const DIG_OUT_DOWN_VISUAL_OFFSET = GNOME_FRAME_HEIGHT - 4.5
# Extra horizontal correction applied only when exiting downward into a tile that required
# the physics-shape clamp to nudge the player sideways (see _snap_to_nearest_adjacent_empty_tile).
const DIG_OUT_DOWN_EXTRA_SIDE_NUDGE = 2.0
const EXPLOSION_HOLD_DURATION = 0.25
const MUSHROOM_BOUNCE_STEER_DURATION = 0.1
const MUSHROOM_BOUNCE_DEBOUNCE_DURATION = 0.08
const DEBUG_DIG_OUT = true
const DEBUG_EARTHWALK = false

# --- IDLE TIMER VARIABLES ---
const IDLE_TIMEOUT = 6.0       # Time in seconds before playing special idle
const IDLE_SIT_TIMEOUT = 12.0
const IDLE_TIRED_TIMEOUT = 20.0
const IDLE_SLEEP_TIMEOUT = 30.0
var idle_timer = 0.0           # Tracks elapsed time since last activity
# Each flips true once idle_timer passes its matching *_TIMEOUT above (progressively deeper idle).
var is_deep_idle = false
var is_deep_idle_sit = false
var is_deep_idle_tired = false
var is_deep_idle_sleep = false

var is_digging = false
var is_digging_out = false
var is_stopped = false
var dig_in_target_cell: Vector2i
var dig_in_direction: Vector2i
var has_dig_in_target = false

var is_earthwalking = false
enum MovementMode { DEFAULT, EARTHWALK }
var movement_mode = MovementMode.DEFAULT
var sprite_rest_position: Vector2
var log_next_default_movement = false

var is_sprinting = false

var is_exploding = false
var mushroom_bounce_normal = Vector2.ZERO
var mushroom_bounce_steer_timer = 0.0
var last_bounced_mushroom: Node2D
var mushroom_bounce_debounce_timer = 0.0
enum WallSmackState { NONE, SMACK, FALL, STUNNED }
var wall_smack_state = WallSmackState.NONE

@export var coyote_time: float = 0.075
var coyote_timer = 0.0


func _ready():
	sprite_rest_position = animated_sprite_2d.position
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	animated_sprite_2d.sprite_frames.set_animation_speed("jumping", 10.0)
	animated_sprite_2d.sprite_frames.set_animation_speed("idlesleep", 0.5)

func _physics_process(delta):
	# Track if the player did any manual action this frame
	var player_active = false
	var direction = 0.0
	mushroom_bounce_debounce_timer = maxf(mushroom_bounce_debounce_timer - delta, 0.0)

	if not is_exploding and not is_earthwalking and movement_mode != MovementMode.EARTHWALK and Input.is_action_just_pressed("explode"):
		_start_explosion()

	if is_exploding:
		velocity = Vector2.ZERO
		return

	if is_digging:
		velocity = Vector2.ZERO
		_update_animations(0.0)
		return

	# Delegate movement to the appropriate movement system.
	# Both movement functions return [player_active: bool, direction: float].
	var movement_result: Array
	if movement_mode == MovementMode.EARTHWALK or is_earthwalking:
		movement_result = _process_earthwalking_movement(delta)
	else:
		movement_result = _process_default_movement(delta)
	player_active = movement_result[0]
	direction = movement_result[1]

	# MOVE THE CHARACTER
	# Only use physics-based movement when not earthwalking
	if not _is_stopped() and not (movement_mode == MovementMode.EARTHWALK or is_earthwalking):
		var impact_velocity = velocity
		move_and_slide()
		_apply_mushroom_bounces(impact_velocity)
		_check_for_wall_smack(impact_velocity)
		_update_wall_smack_landing()

	# IDLE TIMER LOGIC
	if player_active or velocity.x != 0 or not is_on_floor():
		idle_timer = 0.0
		is_deep_idle = false
		is_deep_idle_sit = false
		is_deep_idle_tired = false
		is_deep_idle_sleep = false
	else:
		idle_timer += delta
		if idle_timer >= IDLE_TIMEOUT:
			is_deep_idle = true
		if idle_timer >= IDLE_SIT_TIMEOUT:
			is_deep_idle_sit = true
		if idle_timer >= IDLE_TIRED_TIMEOUT:
			is_deep_idle_tired = true
		if idle_timer >= IDLE_SLEEP_TIMEOUT:
			is_deep_idle_sleep = true

	# ASSIGN ANIMATIONS
	_update_animations(direction)


func _process_default_movement(delta):
	# Returns [player_active, direction]
	if log_next_default_movement:
		_log_dig_out("first default movement")
		log_next_default_movement = false

	var player_active = false
	if wall_smack_state != WallSmackState.NONE and Input.get_axis("left", "right") != 0.0:
		wall_smack_state = WallSmackState.NONE
	# 1. APPLY GRAVITY
	if not is_on_floor() and not is_earthwalking:
		velocity += get_gravity() * delta
		coyote_timer += delta
	else:
		coyote_timer = 0.0

	# 2. HANDLE JUMP
	if Input.is_action_just_pressed("jump") and (is_on_floor() or coyote_timer < coyote_time):
		velocity.y = JUMP_VELOCITY
		player_active = true

	# 3. HANDLE HORIZONTAL MOVEMENT
	var direction = Input.get_axis("left", "right")
	# A mushroom bounce can leave is_on_floor() true on shallow tilts, so grounded input
	# must still go through steering to avoid overwriting the launch velocity.
	var grounded = is_on_floor() and mushroom_bounce_steer_timer <= 0.0
	if direction:
		is_sprinting = Input.is_action_pressed("sprint")
		var target_speed = direction * (SPRINT_SPEED if is_sprinting else SPEED)
		if grounded:
			velocity.x = target_speed
		else:
			var horizontal_change = move_toward(velocity.x, target_speed, AIR_ACCELERATION) - velocity.x
			_apply_air_steering(Vector2(horizontal_change, 0.0), delta)
		animated_sprite_2d.flip_h = (direction < 0)
		player_active = true
	else:
		var deceleration = SPEED if grounded else AIR_DECELERATION
		var horizontal_change = move_toward(velocity.x, 0, deceleration) - velocity.x
		if grounded:
			velocity.x += horizontal_change
		else:
			_apply_air_steering(Vector2(horizontal_change, 0.0), delta)

	# 4. HANDLE DIG
	if Input.is_action_just_pressed("dig") and is_on_floor() and _select_dig_in_target():
		is_digging = true

	return [player_active, direction]


func _process_earthwalking_movement(delta):
	# Earthwalking movement: separated behavior (no gravity, free horizontal control)
	# Returns [player_active, direction]
	var player_active = false
	# For earthwalking we typically ignore gravity so the player can "walk" while
	# in the earthwalking state. Keep jump disabled here to preserve behavior.

	# HORIZONTAL & VERTICAL INPUT
	var directionx = Input.get_axis("left", "right")
	var directiony = Input.get_axis("up", "down")
	if directionx:
		velocity.x = directionx * SPEED
		animated_sprite_2d.flip_h = (directionx < 0)
		player_active = true
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	if directiony:
		velocity.y = directiony * SPEED
		player_active = true
	else:
		velocity.y = move_toward(velocity.y, 0, SPEED)

	# HANDLE DIG (check early so it isn't skipped by movement early-returns)
	if Input.is_action_just_pressed("dig"):
		if _begin_exit_earthwalking():
			return [true, 0.0]

	# Attempt to bind movement to the connected TileMap region (if provided)
	# Attempt to bind movement to the assigned TileMapLayer (if provided)
	var old_pos = global_position
	var desired_pos = old_pos + Vector2(velocity.x, velocity.y) * delta
	var movement_direction = directionx if directionx != 0.0 else directiony

	if tile_map_layer:
		# If desired position is inside the tiles, allow full move
		if _is_world_position_inside_tile(desired_pos):
			global_position = desired_pos
			velocity = Vector2.ZERO
			return [player_active, movement_direction]
		if DEBUG_EARTHWALK and (directionx != 0.0 or directiony != 0.0):
			_log_earthwalk_block(old_pos, desired_pos, Vector2(directionx, directiony))
		# Otherwise try axis-separated moves to allow sliding along bounds
		var try_x = Vector2(old_pos.x + velocity.x * delta, old_pos.y)
		var try_y = Vector2(old_pos.x, old_pos.y + velocity.y * delta)
		var moved = false
		if _is_world_position_inside_tile(try_x):
			global_position.x = try_x.x
			velocity.x = 0
			moved = true
		if _is_world_position_inside_tile(try_y):
			global_position.y = try_y.y
			velocity.y = 0
			moved = true
		if moved:
			return [player_active, movement_direction]
	
	# If no layer or move blocked, leave velocity alone and fall back (no position change)
	return [player_active, movement_direction]


func _apply_mushroom_bounces(impact_velocity: Vector2) -> bool:
	# Check every surface touched this frame for a bounce collider (e.g. a mushroom cap).
	for collision_index in get_slide_collision_count():
		var collision = get_slide_collision(collision_index)
		var collider = collision.get_collider()
		if collider != null and collider.has_method("bounce"):
			# Debounce: skip re-triggering the same mushroom while still resolving its last bounce.
			if collider == last_bounced_mushroom and mushroom_bounce_debounce_timer > 0.0:
				continue
			mushroom_bounce_normal = collider.bounce(self, impact_velocity)
			mushroom_bounce_steer_timer = MUSHROOM_BOUNCE_STEER_DURATION
			last_bounced_mushroom = collider
			mushroom_bounce_debounce_timer = MUSHROOM_BOUNCE_DEBOUNCE_DURATION
			return true
	return false


func _check_for_wall_smack(impact_velocity: Vector2):
	if wall_smack_state != WallSmackState.NONE or absf(impact_velocity.x) < SPRINT_SPEED:
		return

	for collision_index in get_slide_collision_count():
		var collision = get_slide_collision(collision_index)
		var collision_normal = collision.get_normal()
		var collider = collision.get_collider()
		# A near-vertical wall (|normal.x| > 0.5) hit while moving into it (opposing dot product)
		# at sprint speed triggers a smack, but never against bounce surfaces like mushrooms.
		if collider != null and not collider.has_method("bounce") and absf(collision_normal.x) > 0.5 and impact_velocity.dot(collision_normal) < 0.0:
			wall_smack_state = WallSmackState.SMACK
			velocity.x = 0.0
			return


func _update_wall_smack_landing():
	if wall_smack_state == WallSmackState.FALL and is_on_floor():
		wall_smack_state = WallSmackState.STUNNED
	elif wall_smack_state == WallSmackState.STUNNED and not is_on_floor():
		wall_smack_state = WallSmackState.FALL


func _apply_air_steering(steering_change: Vector2, delta: float):
	if mushroom_bounce_steer_timer <= 0.0:
		velocity += steering_change
		return

	mushroom_bounce_steer_timer = maxf(mushroom_bounce_steer_timer - delta, 0.0)
	# Strip out the component of the steering change along the bounce normal (vector
	# projection: change - normal * (change . normal)) so input can't cancel the launch,
	# leaving only the perpendicular (tangential) component to steer with.
	var tangent_change = steering_change - mushroom_bounce_normal * steering_change.dot(mushroom_bounce_normal)
	velocity += tangent_change


func _enter_earthwalking():
	if not has_dig_in_target or not _snap_into_nearest_tile(dig_in_target_cell, dig_in_direction):
		has_dig_in_target = false
		return

	has_dig_in_target = false
	# Disable collision so physics won't push the player out
	is_earthwalking = true
	movement_mode = MovementMode.EARTHWALK
	if collision_shape_2d:
		collision_shape_2d.disabled = true


func _begin_exit_earthwalking() -> bool:
	# Move to the surface before the reverse dig animation begins.
	if not _snap_to_nearest_adjacent_empty_tile():
		return false

	is_earthwalking = false
	movement_mode = MovementMode.DEFAULT
	is_digging_out = true
	is_digging = true
	return true


func _finish_exit_earthwalking():
	if DEBUG_DIG_OUT:
		print("[DIG_OUT] before sprite reset sprite_local=", animated_sprite_2d.position, " sprite_global=", global_position + animated_sprite_2d.position)
	animated_sprite_2d.flip_v = false
	animated_sprite_2d.rotation = 0.0
	animated_sprite_2d.position = sprite_rest_position
	if collision_shape_2d:
		collision_shape_2d.disabled = false
	log_next_default_movement = true
	if DEBUG_DIG_OUT:
		print("[DIG_OUT] after sprite reset sprite_local=", animated_sprite_2d.position, " sprite_global=", global_position + animated_sprite_2d.position)
	_log_dig_out("dig-out animation finished")


func _select_dig_in_target() -> bool:
	if not tile_map_layer:
		return false

	var local_pos = tile_map_layer.to_local(global_position)
	var facing_direction = Vector2i.LEFT if animated_sprite_2d.flip_h else Vector2i.RIGHT
	var held_horizontal_direction = Input.get_axis("left", "right")
	var target_cell: Vector2i
	var target_direction = Vector2i.DOWN

	if held_horizontal_direction != 0.0 and sign(held_horizontal_direction) == facing_direction.x:
		# Holding into the direction the player is facing digs sideways into that tile;
		# the offset samples a point just in front of and slightly above the player's feet.
		var front_position = local_pos + Vector2(facing_direction.x * 8.0, -5.0)
		target_cell = tile_map_layer.local_to_map(front_position)
		target_direction = facing_direction
	else:
		target_cell = tile_map_layer.local_to_map(local_pos + Vector2.DOWN)
		if tile_map_layer.get_cell_source_id(target_cell) == -1:
			# No tile directly below (e.g. straddling an edge): fall back to whichever
			# painted neighboring cell is closest to the player.
			var closest_valid_cell = Vector2i.ZERO
			var shortest_distance = INF

			for cell in tile_map_layer.get_surrounding_cells(target_cell):
				if tile_map_layer.get_cell_source_id(cell) == -1:
					continue

				var cell_world_pos = tile_map_layer.to_global(tile_map_layer.map_to_local(cell))
				var distance_to_cell = global_position.distance_to(cell_world_pos)
				if distance_to_cell < shortest_distance:
					shortest_distance = distance_to_cell
					closest_valid_cell = cell

			if shortest_distance == INF:
				return false

			target_cell = closest_valid_cell

	if not _is_tile_diggable(target_cell) or not _is_tile_earthwalkable(target_cell):
		return false

	dig_in_target_cell = target_cell
	dig_in_direction = target_direction
	has_dig_in_target = true
	return true


func _snap_into_nearest_tile(map_pos: Vector2i, entry_direction: Vector2i) -> bool:
	if not tile_map_layer:
		return false
		
	# 1. Snap into the selected dig target.
	var local_pos = tile_map_layer.to_local(global_position)

	# 2. The target must remain a diggable, earthwalkable painted tile.
	if not _is_tile_diggable(map_pos):
		return false
	if not _is_tile_earthwalkable(map_pos):
		return false

	# 3. Move into the selected tile.
	var center_local = tile_map_layer.map_to_local(map_pos)
	var cell_size = Vector2(tile_map_layer.tile_set.tile_size)
	var cell_min = center_local - cell_size / 2.0
	var cell_max = center_local + cell_size / 2.0
	# Offset the cell bounds by the sprite's footprint so clamping keeps the whole
	# sprite (not just its origin point) within the cell.
	var player_min = cell_min - EARTHWALK_SPRITE_MIN
	var player_max = cell_max - EARTHWALK_SPRITE_MAX - Vector2.ONE * EARTHWALK_BOUNDARY_INSET
	var snapped_local = local_pos.clamp(player_min, player_max)
	if entry_direction == Vector2i.LEFT or entry_direction == Vector2i.RIGHT:
		snapped_local = center_local - (EARTHWALK_SPRITE_MIN + EARTHWALK_SPRITE_MAX) / 2.0
	if entry_direction == Vector2i.DOWN:
		# Prefer keeping the player's current horizontal position if it still fits,
		# so entering from above doesn't snap them sideways.
		var x_preserving_position = Vector2(local_pos.x, snapped_local.y)
		if _is_world_position_inside_tile(tile_map_layer.to_global(x_preserving_position)):
			snapped_local = x_preserving_position
	global_position = tile_map_layer.to_global(snapped_local)
	return true

func _snap_to_nearest_adjacent_empty_tile() -> bool:
	if not tile_map_layer:
		return false
		
	var local_pos = tile_map_layer.to_local(global_position)
	
	# 1. A held direction restricts the search to that adjacent cell.
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var held_direction = Input.get_vector("left", "right", "up", "down")
	if held_direction != Vector2.ZERO:
		if abs(held_direction.x) > abs(held_direction.y):
			directions = [Vector2i.RIGHT if held_direction.x > 0.0 else Vector2i.LEFT]
		else:
			directions = [Vector2i.DOWN if held_direction.y > 0.0 else Vector2i.UP]
	
	var target_empty_cell: Vector2i
	var found_empty_tile: bool = false
	var source_cell: Vector2i
	var largest_overlap: float = -1.0
	var player_rect = Rect2(
		local_pos + EARTHWALK_SPRITE_MIN,
		EARTHWALK_SPRITE_MAX - EARTHWALK_SPRITE_MIN
	)
	var cell_size = Vector2(tile_map_layer.tile_set.tile_size)
	var first_cell = tile_map_layer.local_to_map(player_rect.position)
	var last_cell = tile_map_layer.local_to_map(player_rect.end - Vector2.ONE * EARTHWALK_BOUNDARY_INSET)
	if DEBUG_DIG_OUT:
		print("[DIG_OUT] begin local=", local_pos, " global=", global_position, " held=", held_direction, " cells=", first_cell, "..", last_cell)
	
	# 2. Find the most-overlapped earthwalk cell with an empty neighbor in the exit direction.
	for cell_x in range(first_cell.x, last_cell.x + 1):
		for cell_y in range(first_cell.y, last_cell.y + 1):
			var current_cell = Vector2i(cell_x, cell_y)
			if not _is_tile_earthwalkable(current_cell):
				continue

			var cell_center = tile_map_layer.map_to_local(current_cell)
			var cell_rect = Rect2(cell_center - cell_size / 2.0, cell_size)
			var overlap = player_rect.intersection(cell_rect).get_area()
			for dir in directions:
				var check_cell = current_cell + dir
				if _is_tile_empty_for_dig_out(check_cell) and overlap > largest_overlap:
					if DEBUG_DIG_OUT:
						print("[DIG_OUT] candidate source=", current_cell, " target=", check_cell, " direction=", dir, " overlap=", overlap)
					target_empty_cell = check_cell
					source_cell = current_cell
					largest_overlap = overlap
					found_empty_tile = true

	# 3. If an empty neighbor was found, snap to its nearest point.
	if found_empty_tile:
		var exit_direction = target_empty_cell - source_cell
		_set_dig_out_orientation(exit_direction)
		var center_local = tile_map_layer.map_to_local(target_empty_cell)
		var cell_min = center_local - cell_size / 2.0
		var cell_max = center_local + cell_size / 2.0
		# Mirrors _snap_into_nearest_tile's containment clamp, but only requires the collision
		# shape's center (half its extents) to clear the cell bounds rather than its full size,
		# since the player may start deeply embedded in the solid tile being left behind and a
		# full-size clamp would shove them further than necessary.
		var collision_bounds = _get_collision_local_bounds()
		var half_collision_min = collision_bounds[0] / 2.0
		var half_collision_max = collision_bounds[1] / 2.0
		var player_min = cell_min - half_collision_min
		var player_max = cell_max - half_collision_max - Vector2.ONE * EARTHWALK_BOUNDARY_INSET
		var snapped_local = local_pos.clamp(player_min, player_max)
		# The dig-out sprite is drawn slightly off-center, so when exiting downward into a tile
		# that needed horizontal clamping, nudge a bit further the same way to keep it aligned.
		if exit_direction == Vector2i.DOWN:
			var horizontal_nudge_direction = signf(snapped_local.x - local_pos.x)
			snapped_local.x += horizontal_nudge_direction * DIG_OUT_DOWN_EXTRA_SIDE_NUDGE
		global_position = tile_map_layer.to_global(snapped_local)
		if DEBUG_DIG_OUT:
			print("[DIG_OUT] selected source=", source_cell, " target=", target_empty_cell, " cell_min=", cell_min, " cell_max=", cell_max, " player_min=", player_min, " player_max=", player_max, " snapped local=", snapped_local, " global=", global_position)
		return true

	if DEBUG_DIG_OUT:
		print("[DIG_OUT] no adjacent empty tile found")
	return false


func _log_dig_out(stage: String):
	if not DEBUG_DIG_OUT:
		return

	var local_pos = tile_map_layer.to_local(global_position) if tile_map_layer else global_position
	var map_pos = tile_map_layer.local_to_map(local_pos) if tile_map_layer else Vector2i.ZERO
	var collision_pos = collision_shape_2d.global_position if collision_shape_2d else global_position
	print("[DIG_OUT] ", stage, " global=", global_position, " local=", local_pos, " map=", map_pos, " collision=", collision_pos, " velocity=", velocity)


func _log_earthwalk_block(old_position: Vector2, desired_position: Vector2, input_direction: Vector2):
	var corners = [
		desired_position + EARTHWALK_SPRITE_MIN,
		desired_position + Vector2(EARTHWALK_SPRITE_MAX.x - EARTHWALK_BOUNDARY_INSET, EARTHWALK_SPRITE_MIN.y),
		desired_position + Vector2(EARTHWALK_SPRITE_MIN.x, EARTHWALK_SPRITE_MAX.y - EARTHWALK_BOUNDARY_INSET),
		desired_position + EARTHWALK_SPRITE_MAX - Vector2.ONE * EARTHWALK_BOUNDARY_INSET,
	]
	print("[EARTHWALK] blocked input=", input_direction, " old=", old_position, " desired=", desired_position)
	for corner in corners:
		var cell = tile_map_layer.local_to_map(tile_map_layer.to_local(corner))
		print("[EARTHWALK] corner=", corner, " cell=", cell, " source_id=", tile_map_layer.get_cell_source_id(cell), " earthwalkable=", _is_tile_earthwalkable(cell))


func _set_dig_out_orientation(exit_direction: Vector2i):
	animated_sprite_2d.flip_v = false
	animated_sprite_2d.rotation = 0.0
	animated_sprite_2d.position = sprite_rest_position

	match exit_direction:
		Vector2i.DOWN:
			animated_sprite_2d.flip_v = true
			animated_sprite_2d.position.y += DIG_OUT_DOWN_VISUAL_OFFSET
		Vector2i.LEFT:
			animated_sprite_2d.rotation = -PI / 2.0
			# Rotate the rest position by the opposite angle so the sprite's local offset
			# still points in the same world-space direction once the node itself is rotated.
			animated_sprite_2d.position = sprite_rest_position.rotated(PI / 2.0)
		Vector2i.RIGHT:
			animated_sprite_2d.rotation = PI / 2.0
			animated_sprite_2d.position = sprite_rest_position.rotated(-PI / 2.0)

	if exit_direction == Vector2i.LEFT or exit_direction == Vector2i.RIGHT:
		animated_sprite_2d.position.x += exit_direction.x * DIG_OUT_SIDE_VISUAL_OFFSET
		animated_sprite_2d.position.y += DIG_OUT_SIDE_VERTICAL_OFFSET

	if DEBUG_DIG_OUT:
		print("[DIG_OUT] sprite orientation exit_direction=", exit_direction, " sprite_local=", animated_sprite_2d.position, " sprite_global=", global_position + animated_sprite_2d.position, " flip_v=", animated_sprite_2d.flip_v, " rotation=", animated_sprite_2d.rotation)


func _is_tile_diggable(cell: Vector2i) -> bool:
	var tile_data = tile_map_layer.get_cell_tile_data(cell)
	return tile_data != null and tile_data.get_custom_data("can_dig") != false


func _is_tile_earthwalkable(cell: Vector2i) -> bool:
	var tile_data = tile_map_layer.get_cell_tile_data(cell)
	return tile_data != null and tile_data.get_custom_data("can_earthwalk") != false


func _is_tile_empty_for_dig_out(cell: Vector2i) -> bool:
	if tile_map_layer.get_cell_source_id(cell) == -1:
		return true

	var tile_data = tile_map_layer.get_cell_tile_data(cell)
	return tile_data != null and tile_data.get_custom_data("empty") == true


# Helper that checks whether the full sprite lies inside earthwalkable tiles of the layer.
func _is_world_position_inside_tile(world_position: Vector2) -> bool:
	if not tile_map_layer:
		return false

	var corners = [
		world_position + EARTHWALK_SPRITE_MIN,
		world_position + Vector2(EARTHWALK_SPRITE_MAX.x - EARTHWALK_BOUNDARY_INSET, EARTHWALK_SPRITE_MIN.y),
		world_position + Vector2(EARTHWALK_SPRITE_MIN.x, EARTHWALK_SPRITE_MAX.y - EARTHWALK_BOUNDARY_INSET),
		world_position + EARTHWALK_SPRITE_MAX - Vector2.ONE * EARTHWALK_BOUNDARY_INSET,
	]

	for corner in corners:
		var local_pos = tile_map_layer.to_local(corner)
		var map_pos = tile_map_layer.local_to_map(local_pos)
		if not _is_tile_earthwalkable(map_pos):
			return false

	return true


# Returns the physics collision shape's local-space [min, max] bounds around its center;
# used to find the minimal shift needed to clear solid geometry (smaller than the earthwalk box).
func _get_collision_local_bounds() -> Array:
	if not collision_shape_2d or not collision_shape_2d.shape:
		return [Vector2.ZERO, Vector2.ZERO]

	var shape = collision_shape_2d.shape
	var half_extents = Vector2.ZERO
	if shape is RectangleShape2D:
		half_extents = shape.size / 2.0
	elif shape is CircleShape2D:
		half_extents = Vector2.ONE * shape.radius

	return [collision_shape_2d.position - half_extents, collision_shape_2d.position + half_extents]


func _is_stopped():
	return is_digging || is_stopped


func _start_explosion():
	is_exploding = true
	velocity = Vector2.ZERO
	animated_sprite_2d.play("explode")
	
func _on_animation_finished():
	if is_exploding and animated_sprite_2d.animation == "explode":
		await get_tree().create_timer(EXPLOSION_HOLD_DURATION).timeout
		get_tree().reload_current_scene()
		return

	if wall_smack_state == WallSmackState.SMACK and animated_sprite_2d.animation == "wallsmack":
		wall_smack_state = WallSmackState.FALL
		return

	if animated_sprite_2d.animation == _get_dig_animation():
		if is_digging:
			if is_digging_out:
				_finish_exit_earthwalking()
			else:
				_enter_earthwalking()
		is_digging = false
		is_digging_out = false
	

func _get_dig_animation() -> StringName:
	if not is_digging_out and (dig_in_direction == Vector2i.LEFT or dig_in_direction == Vector2i.RIGHT):
		return &"side_dig"
	return &"dig"


# Plays an animation only if it isn't already the current one, avoiding restart-on-every-frame flicker.
func _play_if_different(animation_name: StringName):
	if animated_sprite_2d.animation != animation_name:
		animated_sprite_2d.play(animation_name)


func _update_animations(direction: float):
	if is_digging:
		var dig_animation = _get_dig_animation()
		if animated_sprite_2d.animation != dig_animation:
			if is_digging_out:
				animated_sprite_2d.play_backwards("dig")
			else:
				animated_sprite_2d.flip_h = dig_in_direction == Vector2i.LEFT
				animated_sprite_2d.play(dig_animation)
		return

	if wall_smack_state != WallSmackState.NONE:
		var wall_smack_animation = &"wallsmack"
		if wall_smack_state == WallSmackState.FALL:
			wall_smack_animation = &"fallafterwallsmack"
		elif wall_smack_state == WallSmackState.STUNNED:
			wall_smack_animation = &"stunnedextended"
		_play_if_different(wall_smack_animation)
		return

	if is_earthwalking:
		_play_if_different(&"earthwalk")
		if direction != 0:
			if animated_sprite_2d.animation == "earthwalk" && !animated_sprite_2d.is_playing():
				animated_sprite_2d.play()
		else:
			animated_sprite_2d.pause()
		return
	elif is_on_floor():
		if direction != 0:
			_play_if_different(&"sprinting" if is_sprinting else &"walking")
		else:
			# Deepening idle stages are checked from longest to shortest timeout so the
			# most "asleep" animation that has been earned wins.
			if is_deep_idle_sleep:
				_play_if_different(&"idlesleep")
			elif is_deep_idle_tired:
				_play_if_different(&"idletired")
			elif is_deep_idle_sit:
				_play_if_different(&"idlesit")
			elif is_deep_idle:
				_play_if_different(&"idle")
			else:
				_play_if_different(&"default")
	else:
		_play_if_different(&"jumping" if velocity.y < 0 else &"falling")
