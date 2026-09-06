extends StaticBody2D

@onready var animated_sprite_2d = $AnimatedSprite2D

# The strength of the launch force
@export var bounce_force: float = 1.0
@export_range(0.0, 1.0, 0.01) var force_multiplier: float = 0.2

func _on_ready():
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)

func _on_animation_finished():
	if animated_sprite_2d.animation == "Animation":
		animated_sprite_2d.play("Default")

func bounce(body: CharacterBody2D, impact_velocity: Vector2) -> void:
	animated_sprite_2d.play("Animation")
	
	# transform.y is local down; its inverse launches away from the mushroom surface.
	var launch_direction = -global_transform.y
	var impact_speed = maxf(impact_velocity.dot(-launch_direction), 0.0)
	if impact_speed <= 0.0:
		return

	# Scale bounce height from the speed moving into the pad, not by adding it.
	var launch_speed = maxf(bounce_force, impact_speed * force_multiplier)
	body.velocity = launch_direction * launch_speed
