extends Node

# SettingsManager - Manages game settings including FPS limits and performance options

const SETTINGS_FILE = "user://settings.cfg"

var target_fps: int = 120  # Default FPS (optimized for Razer Edge 5G 120Hz display)
var settings_loaded: bool = false

# Performance optimization settings
var fsr_quality: int = 2  # 0=Low (75%), 1=Medium (90%), 2=High (100%)
var occlusion_culling: bool = true
var adaptive_quality: bool = false
var use_multimesh_vegetation: bool = false  # Future: Use MultiMesh for vegetation
var merge_block_meshes: bool = false  # Future: Merge blocks into chunk meshes
var chunk_physics_only: bool = false  # Future: One physics body per chunk
var face_culling: bool = true  # Cull hidden block faces
var max_render_distance: int = 2  # Maximum chunks to render (reduced = better FPS)

signal fps_changed(new_fps: int)
signal performance_settings_changed()

func _ready():
	load_settings()
	apply_fps_limit()

func load_settings():
	# Load settings from config file
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)
	
	if err == OK:
		target_fps = config.get_value("performance", "target_fps", 120)
		fsr_quality = config.get_value("performance", "fsr_quality", 2)
		occlusion_culling = config.get_value("performance", "occlusion_culling", true)
		adaptive_quality = config.get_value("performance", "adaptive_quality", false)
		use_multimesh_vegetation = config.get_value("performance", "use_multimesh_vegetation", false)
		merge_block_meshes = config.get_value("performance", "merge_block_meshes", false)
		chunk_physics_only = config.get_value("performance", "chunk_physics_only", false)
		face_culling = config.get_value("performance", "face_culling", true)
		max_render_distance = config.get_value("performance", "max_render_distance", 2)
		settings_loaded = true
	else:
		# First time - use defaults
		target_fps = 120
		fsr_quality = 2
		occlusion_culling = true
		adaptive_quality = false
		use_multimesh_vegetation = false
		merge_block_meshes = false
		chunk_physics_only = false
		face_culling = true
		max_render_distance = 2
		settings_loaded = true
	
	apply_fps_limit()
	apply_performance_settings()

func save_settings():
	# Save settings to config file
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)  # Try to load existing first
	if err != OK:
		config = ConfigFile.new()  # Create new if doesn't exist
	
	config.set_value("performance", "target_fps", target_fps)
	config.set_value("performance", "fsr_quality", fsr_quality)
	config.set_value("performance", "occlusion_culling", occlusion_culling)
	config.set_value("performance", "adaptive_quality", adaptive_quality)
	config.set_value("performance", "use_multimesh_vegetation", use_multimesh_vegetation)
	config.set_value("performance", "merge_block_meshes", merge_block_meshes)
	config.set_value("performance", "chunk_physics_only", chunk_physics_only)
	config.set_value("performance", "face_culling", face_culling)
	config.set_value("performance", "max_render_distance", max_render_distance)
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

# Performance settings functions
func set_fsr_quality(quality: int):
	fsr_quality = clamp(quality, 0, 2)
	save_settings()
	apply_performance_settings()
	performance_settings_changed.emit()

func set_occlusion_culling(enabled: bool):
	occlusion_culling = enabled
	save_settings()
	apply_performance_settings()
	performance_settings_changed.emit()

func set_adaptive_quality(enabled: bool):
	adaptive_quality = enabled
	save_settings()
	apply_performance_settings()
	performance_settings_changed.emit()

func set_use_multimesh_vegetation(enabled: bool):
	use_multimesh_vegetation = enabled
	save_settings()
	apply_performance_settings()
	performance_settings_changed.emit()

func set_merge_block_meshes(enabled: bool):
	merge_block_meshes = enabled
	save_settings()
	apply_performance_settings()
	performance_settings_changed.emit()

func set_chunk_physics_only(enabled: bool):
	chunk_physics_only = enabled
	save_settings()
	apply_performance_settings()
	performance_settings_changed.emit()

func set_face_culling(enabled: bool):
	face_culling = enabled
	save_settings()
	apply_performance_settings()
	performance_settings_changed.emit()

func set_max_render_distance(distance: int):
	max_render_distance = clamp(distance, 1, 8)
	save_settings()
	apply_performance_settings()
	performance_settings_changed.emit()

func apply_performance_settings():
	# Apply FSR/Viewport scaling
	var viewport = get_tree().root.get_viewport() if get_tree() else null
	if viewport:
		var viewport_rid = viewport.get_viewport_rid()
		match fsr_quality:
			0:  # Low - 75% resolution
				RenderingServer.viewport_set_scaling_3d_mode(viewport_rid, RenderingServer.VIEWPORT_SCALING_3D_MODE_BILINEAR)
				RenderingServer.viewport_set_scaling_3d_scale(viewport_rid, 0.75)
			1:  # Medium - 90% resolution
				RenderingServer.viewport_set_scaling_3d_mode(viewport_rid, RenderingServer.VIEWPORT_SCALING_3D_MODE_BILINEAR)
				RenderingServer.viewport_set_scaling_3d_scale(viewport_rid, 0.9)
			2:  # High - 100% resolution
				RenderingServer.viewport_set_scaling_3d_mode(viewport_rid, RenderingServer.VIEWPORT_SCALING_3D_MODE_BILINEAR)
				RenderingServer.viewport_set_scaling_3d_scale(viewport_rid, 1.0)
	
	# Apply occlusion culling
	# Note: Occlusion culling is a project setting that requires restart to change
	# We can't change it at runtime in Godot 4, so this setting is informational
	# The user can enable/disable it in project settings and restart the game
	# We'll just save the preference for future reference
	# ProjectSettings.set_setting("rendering/occlusion_culling/use_occlusion_culling", occlusion_culling)
	# Note: Changing project settings at runtime doesn't work reliably, so we skip this
	
	# Apply adaptive quality to FrameGen
	var frame_gen = get_node_or_null("/root/FrameGen")
	if frame_gen and frame_gen.has_method("set_adaptive_quality"):
		frame_gen.set_adaptive_quality(adaptive_quality)
	
	# Notify World about render distance changes and other settings
	if get_tree():
		var world = get_tree().get_first_node_in_group("world")
		if world:
			if world.has_method("set_render_distance"):
				world.set_render_distance(max_render_distance)
			if world.has_method("set_merge_block_meshes"):
				world.set_merge_block_meshes(merge_block_meshes)
			if world.has_method("set_use_multimesh_vegetation"):
				world.set_use_multimesh_vegetation(use_multimesh_vegetation)
			if world.has_method("set_chunk_physics_only"):
				world.set_chunk_physics_only(chunk_physics_only)
			if world.has_method("set_face_culling"):
				world.set_face_culling(face_culling)

