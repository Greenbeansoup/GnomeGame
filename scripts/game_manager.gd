extends Node2D

# Preload your scenes for easy swapping
@export var level_1_scene: PackedScene
@export var test_arena_scene: PackedScene
@export var main_menu_scene: PackedScene
@export var chase_music: AudioStream = preload("res://assets/music/NastyRat.wav")
@export_range(0.0, 5.0, 0.05) var background_music_resume_delay := 0.75
@export_range(0.0, 5.0, 0.05) var background_music_fade_in_duration := 1.0

@onready var pause_menu = $UI/PauseMenu
@onready var menu_holder = $UI/MenuHolder
@onready var ui_layer = $UI
@onready var current_scene_holder = $CurrentScene
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var background_music: AudioStream = music_player.stream
@onready var music_volume: float = music_player.volume_linear

var current_level_scene: PackedScene
var chase_music_sources: Dictionary = {}
var background_music_position := 0.0
var chase_music_position := 0.0
var background_music_resume_timer := Timer.new()
var music_fade_tween: Tween
# The last PlayerSpawn marker a chunk reported the player reaching; survives level
# restarts (death/respawn) but resets whenever a level is started fresh.
var last_spawn_position: Vector2
var has_last_spawn := false

func _ready():
	add_to_group("game_manager")
	process_mode = Node.PROCESS_MODE_ALWAYS
	background_music_resume_timer.one_shot = true
	add_child(background_music_resume_timer)
	background_music_resume_timer.timeout.connect(_resume_background_music)
	# Start by showing the main menu
	show_main_menu()
	
	# Hide the pause menu immediately when the game boots up
	pause_menu.hide()
	
	# Connect the buttons from inside your pause menu scene
	pause_menu.resume_pressed.connect(_on_resume_pressed)
	pause_menu.main_menu_pressed.connect(_on_main_menu_pressed)
	pause_menu.exit_pressed.connect(_on_exit_pressed)

func _unhandled_input(event: InputEvent):
	# 1. Check if the event is your pause action
	# 2. Make sure it's a down-press, not a release
	# 3. CRUCIAL: Make sure it's not an "echo" repeat from holding the key!
	if event.is_action_pressed("pause") and not event.is_echo():
		
		# 4. Stop the input from passing to any other nodes this frame
		get_viewport().set_input_as_handled()
		toggle_pause()

func show_main_menu():
	current_level_scene = null
	has_last_spawn = false
	# Clear out the temporary menus, but the PauseMenu is safe!
	_clear_children(menu_holder) 
	_clear_children(current_scene_holder)
	
	var menu = main_menu_scene.instantiate()
	menu_holder.add_child(menu) # Put it inside the holder
	menu.start_game_pressed.connect(start_level.bind(level_1_scene))
	menu.start_test_arena_pressed.connect(start_level.bind(test_arena_scene))
	menu.exit_pressed.connect(_on_exit_pressed)

func set_chase_music_active(source: Node, active: bool) -> void:
	var source_id := source.get_instance_id()
	if active:
		if chase_music_sources.has(source_id) or not chase_music:
			return
		chase_music_sources[source_id] = true
		if chase_music_sources.size() == 1:
			background_music_resume_timer.stop()
			if music_fade_tween:
				music_fade_tween.kill()
			music_player.volume_linear = music_volume
			if music_player.stream == background_music:
				background_music_position = music_player.get_playback_position()
			music_player.stream = chase_music
			music_player.play(chase_music_position)
	else:
		if not chase_music_sources.has(source_id):
			return
		chase_music_sources.erase(source_id)
		if chase_music_sources.is_empty():
			chase_music_position = music_player.get_playback_position()
			music_player.stop()
			if background_music_resume_delay <= 0.0:
				_resume_background_music()
			else:
				background_music_resume_timer.start(background_music_resume_delay)


func _resume_background_music() -> void:
	if not chase_music_sources.is_empty():
		return
	if music_fade_tween:
		music_fade_tween.kill()
	music_player.stream = background_music
	music_player.volume_linear = 0.0 if background_music_fade_in_duration > 0.0 else music_volume
	music_player.play(background_music_position)
	if background_music_fade_in_duration > 0.0:
		music_fade_tween = create_tween()
		music_fade_tween.tween_property(music_player, "volume_linear", music_volume, background_music_fade_in_duration)


func _on_exit_pressed():
	get_tree().quit()
		
func toggle_pause():
	if get_tree().paused:
		get_tree().paused = false
		pause_menu.hide()
	else:
		get_tree().paused = true
		pause_menu.show()

func _on_resume_pressed():
	toggle_pause() # Unpauses and hides the menu

func _on_main_menu_pressed():
	toggle_pause() # Must unpause the tree first so things process normally!
	show_main_menu() # Run your existing function to load the main menu

func start_level(level_scene: PackedScene):
	current_level_scene = level_scene
	has_last_spawn = false
	# Remove the main menu
	_clear_children(menu_holder)
	_replace_current_level()

func restart_current_level():
	if not current_level_scene:
		return
	get_tree().paused = false
	pause_menu.hide()
	_replace_current_level()


# Death/respawn path: keeps the current level (camera, chunk loader) intact instead of
# rebuilding the whole scene, so the camera doesn't snap back to the level's start.
func respawn_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		restart_current_level()
		return

	var spawn_position := get_spawn_position(player.global_position)
	# Move the player away first so a recreated hazard/enemy doesn't immediately
	# re-detect them still standing at the death position.
	if player.has_method("respawn_at"):
		player.respawn_at(spawn_position)
	var chunk_loader = get_tree().get_first_node_in_group("chunk_loader")
	if chunk_loader and chunk_loader.has_method("reload_active_chunks"):
		chunk_loader.reload_active_chunks()


func _replace_current_level():
	_clear_children(current_scene_holder)
	var level := current_level_scene.instantiate()
	current_scene_holder.add_child(level)


func set_last_spawn(spawn_position: Vector2) -> void:
	last_spawn_position = spawn_position
	has_last_spawn = true


func get_spawn_position(default_position: Vector2) -> Vector2:
	return last_spawn_position if has_last_spawn else default_position

func _clear_children(target_node: Node):
	for child in target_node.get_children():
		child.queue_free()
