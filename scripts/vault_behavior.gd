class_name VaultBehavior
extends Node

@export var actor: CharacterBody2D
@export var body_shape: CollisionShape2D
@export var enabled := true
@export_range(1.0, 64.0, 1.0) var obstacle_height := 16.0
@export_range(1.0, 32.0, 1.0) var probe_distance := 12.0
@export var jump_velocity := -200.0
@export var retry_jump_velocity := -300.0
@export_range(1, 5, 1) var max_attempts := 2

var jump_attempts := 0
var jump_pending := false
var last_jump_position := Vector2.ZERO


func _ready() -> void:
	if actor == null:
		actor = get_parent() as CharacterBody2D
	assert(actor != null, "VaultBehavior needs a CharacterBody2D actor")
	assert(body_shape != null and body_shape.shape != null, "VaultBehavior needs a body CollisionShape2D")


func update() -> void:
	if not enabled or is_zero_approx(actor.velocity.x):
		reset()
		return
	if jump_attempts > 0 and absf(actor.global_position.x - last_jump_position.x) >= probe_distance:
		jump_attempts = 0
	var obstacle_ahead := has_low_obstacle_ahead(signf(actor.velocity.x))
	if obstacle_ahead:
		jump_pending = true
	if actor.is_on_floor() and jump_pending and jump_attempts < max_attempts:
		jump_attempts += 1
		last_jump_position = actor.global_position
		actor.velocity.y = jump_velocity if jump_attempts == 1 else retry_jump_velocity
		jump_pending = false
	elif actor.is_on_floor() and not obstacle_ahead:
		reset()


func reset() -> void:
	jump_attempts = 0
	jump_pending = false


func has_low_obstacle_ahead(direction: float) -> bool:
	var body_rect := body_shape.shape.get_rect()
	var foot_position := body_shape.to_global(Vector2(body_rect.get_center().x, body_rect.end.y))
	var probe_origin := foot_position - Vector2(0.0, 1.0)
	var half_width := absf(body_shape.global_transform.x.x) * body_rect.size.x * 0.5
	var probe_offset := Vector2(direction * (half_width + probe_distance), 0.0)
	var query := PhysicsRayQueryParameters2D.create(probe_origin, probe_origin + probe_offset)
	query.exclude = [actor.get_rid()]
	query.collision_mask = actor.collision_mask
	query.hit_from_inside = true
	if not actor.get_world_2d().direct_space_state.intersect_ray(query):
		return false
	var clearance_origin := probe_origin - Vector2(0.0, obstacle_height)
	query.from = clearance_origin
	query.to = clearance_origin + probe_offset
	return actor.get_world_2d().direct_space_state.intersect_ray(query).is_empty()