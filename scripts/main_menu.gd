extends Control

@onready var start = $VBoxContainer/Start
@onready var exit = $VBoxContainer/Exit
@onready var start_test_arena = $VBoxContainer/StartTestArena

signal start_game_pressed
signal exit_pressed
signal start_test_arena_pressed

func _ready():
	start.pressed.connect(_on_start_pressed)
	exit.pressed.connect(_on_exit_pressed)
	start_test_arena.pressed.connect(_on_start_test_arena_pressed)

func _on_start_pressed():
	start_game_pressed.emit()
	
func _on_start_test_arena_pressed():
	start_test_arena_pressed.emit()

func _on_exit_pressed():
	exit_pressed.emit()
