extends Control

@onready var start = $VBoxContainer/Start
@onready var exit = $VBoxContainer/Exit
@onready var start_test_arena = $VBoxContainer/StartTestArena

func _ready():
	start.pressed.connect(_on_start_pressed)
	exit.pressed.connect(_on_exit_pressed)
	start_test_arena.pressed.connect(_on_start_test_arena_pressed)


func _on_start_pressed():
	get_tree().change_scene_to_file("res://levels/game.tscn")
	
func _on_start_test_arena_pressed():
	get_tree().change_scene_to_file("res://levels/TestArena.tscn")


func _on_exit_pressed():
	get_tree().quit()
