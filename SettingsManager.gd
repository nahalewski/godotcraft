extends Node

# SettingsManager - Manages game settings including FPS limits

const SETTINGS_FILE = "user://settings.cfg"

var target_fps: int = 120  # Default FPS (optimized for Razer Edge 5G 120Hz display)
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
		target_fps = config.get_value("performance", "target_fps", 120)
		settings_loaded = true
	else:
		# First time - use defaults (120 FPS for Razer Edge 5G)
		target_fps = 120
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
	# Also update FrameGen if it exists
	var frame_gen = get_node_or_null("/root/FrameGen")
	if frame_gen:
		frame_gen.set_target_fps(target_fps)
	# Only print in debug builds
	if OS.is_debug_build():
		print("FPS limit set to: ", target_fps)

func get_target_fps() -> int:
	return target_fps

