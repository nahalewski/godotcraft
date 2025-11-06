extends Node

# AndroidOptimizer - Optimizes game settings for Android devices, specifically Razer Edge 5G
# Auto-detects Android and applies performance optimizations

func _ready():
	if OS.get_name() == "Android":
		optimize_for_android()
		print("Android optimizations applied for Razer Edge 5G")

func optimize_for_android():
	# Force landscape orientation on Android
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	
	# Set target FPS to 120 for Razer Edge 5G (high refresh rate display)
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		# Default to 120 FPS on Android for Razer Edge unless user has set a preference
		if not settings_manager.settings_loaded:
			settings_manager.set_target_fps(120)
	
	# Enable VSync on Android to prevent screen tearing
	# Use adaptive VSync if available, otherwise enabled
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	
	# Optimize rendering for mobile
	RenderingServer.viewport_set_debug_draw(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_DEBUG_DRAW_DISABLED)
	
	# Reduce physics update rate slightly for better performance
	Engine.physics_ticks_per_second = 60

