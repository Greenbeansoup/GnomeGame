extends CharacterBody2D

@export_enum("Left:-1", "Right:1") var start_facing: int = -1

@onready var pursuit: PursuitBehavior = $PursuitBehavior
@onready var vault = $VaultBehavior
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sprite_left_position: Vector2 = sprite.position


func _ready() -> void:
	pursuit.facing_direction = float(start_facing)
	pursuit.aggro_sight.scale.x = -pursuit.facing_direction
	_on_facing_changed(pursuit.facing_direction)
	pursuit.facing_changed.connect(_on_facing_changed)
	sprite.play(&"default")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	pursuit.update(delta)
	vault.update()
	move_and_slide()


func _on_facing_changed(direction: float) -> void:
	sprite.flip_h = direction > 0.0
	sprite.position.x = -sprite_left_position.x if sprite.flip_h else sprite_left_position.x
