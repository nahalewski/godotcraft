extends Node

# SettingsManager - Manages game settings including FPS limits

const SETTINGS_FILE = "user://settings.cfg"

var target_fps: int = 60  # Default FPS
var settings_loaded: bool = false

signal fps_changed(new_fps: int)

func _ready():
	load_settings()
	apply_fps_limit()

func load_settings():
	# Load settings from config file
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)
	
	if err == OK:
		target_fps = config.get_value("performance", "target_fps", 60)
		settings_loaded = true
	else:
		# First time - use defaults
		target_fps = 60
		settings_loaded = true
	
	apply_fps_limit()

func save_settings():
	# Save settings to config file
	var config = ConfigFile.new()
	config.set_value("performance", "target_fps", target_fps)
	config.save(SETTINGS_FILE)

func set_target_fps(fps: int):
	target_fps = fps
	save_settings()
	apply_fps_limit()
	fps_changed.emit(fps)

func apply_fps_limit():
	# Set the FPS limit
	Engine.max_fps = target_fps
	print("FPS limit set to: ", target_fps)

func get_target_fps() -> int:
	return target_fps

