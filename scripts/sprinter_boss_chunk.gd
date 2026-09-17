extends WorldChunk

@export var sprinter_boss_scene: PackedScene

@onready var sprinter_rat_spawn: Marker2D = $SprinterRatSpawn

@export var sprinter_boss_attack_range: float = 64.0
@export var sprinter_boss_chase_speed: float = 184.0


func _ready() -> void:
	var sprinter_boss := sprinter_boss_scene.instantiate() as CharacterBody2D
	sprinter_boss.name = "SprinterRat"
	sprinter_boss.set("attack_range", sprinter_boss_attack_range)
	sprinter_boss.set("chase_speed", sprinter_boss_chase_speed)
	sprinter_boss.position = sprinter_rat_spawn.position
	add_child(sprinter_boss)