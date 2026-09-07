extends StaticBody2D

@onready var animated_sprite_2d = $AnimatedSprite2D

# The strength of the launch force
@export var bounce_force: float = 1.0
@export_range(0.0, 1.0, 0.01) var force_multiplier: float = 0.2

func _on_ready():
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)

func _on_animation_finished():
	if animated_sprite_2d.animation == "Bounce":
		animated_sprite_2d.play("Default")

func bounce(body: CharacterBody2D, impact_velocity: Vector2) -> Vector2:
	animated_sprite_2d.play("Bounce")
	
	# transform.y is local down; its inverse launches away from the mushroom surface.
	var launch_direction = -global_transform.y
	var impact_speed = absf(impact_velocity.dot(-launch_direction))

	# Preserve a minimum bounce while allowing stronger impacts in the same axis to scale it.
	var launch_speed = maxf(bounce_force, impact_speed * force_multiplier)
	var tangential_velocity = impact_velocity - launch_direction * impact_velocity.dot(launch_direction)
	body.velocity = tangential_velocity + launch_direction * launch_speed
	return launch_direction
