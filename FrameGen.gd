extends Node

# FrameGen - Frame generation and frame pacing optimization
# Helps maintain consistent frame rates and reduces stuttering

signal frame_rate_changed(new_fps: float)

var target_fps: int = 60
var current_fps: float = 60.0
var frame_time_history: Array[float] = []
var frame_time_history_size: int = 60  # Track last 60 frames

var adaptive_quality_enabled: bool = true
var quality_level: int = 2  # 0=low, 1=medium, 2=high

func _ready():
	# Initialize with current target FPS from SettingsManager
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		target_fps = settings_manager.get_target_fps()
		set_target_fps(target_fps)
	
	# Start frame monitoring
	set_process(true)

func _process(_delta):
	# Track frame times for adaptive quality
	var frame_time = 1.0 / Engine.get_frames_per_second() if Engine.get_frames_per_second() > 0 else 1.0 / 60.0
	frame_time_history.append(frame_time)
	
	if frame_time_history.size() > frame_time_history_size:
		frame_time_history.pop_front()
	
	# Update current FPS
	current_fps = Engine.get_frames_per_second()
	
	# Adaptive quality adjustment
	if adaptive_quality_enabled and frame_time_history.size() >= 30:
		adjust_quality_based_on_performance()

func adjust_quality_based_on_performance():
	# Calculate average frame time over recent frames
	var avg_frame_time = 0.0
	for time in frame_time_history:
		avg_frame_time += time
	avg_frame_time /= frame_time_history.size()
	
	var target_frame_time = 1.0 / float(target_fps)
	var performance_ratio = avg_frame_time / target_frame_time
	
	# Adjust quality if performance is struggling
	if performance_ratio > 1.2 and quality_level > 0:
		# Performance is below target, reduce quality
		quality_level -= 1
		apply_quality_settings()
	elif performance_ratio < 0.8 and quality_level < 2:
		# Performance is above target, increase quality
		quality_level += 1
		apply_quality_settings()

func apply_quality_settings():
	# Apply quality settings based on current quality level
	# Get the main viewport
	var viewport = get_viewport()
	if not viewport:
		return
	
	var viewport_rid = viewport.get_viewport_rid()
	
	match quality_level:
		0:  # Low quality - render at 75% scale and upscale
			RenderingServer.viewport_set_scaling_3d_mode(viewport_rid, RenderingServer.VIEWPORT_SCALING_3D_MODE_BILINEAR)
			RenderingServer.viewport_set_scaling_3d_scale(viewport_rid, 0.75)
		1:  # Medium quality - render at 90% scale and upscale
			RenderingServer.viewport_set_scaling_3d_mode(viewport_rid, RenderingServer.VIEWPORT_SCALING_3D_MODE_BILINEAR)
			RenderingServer.viewport_set_scaling_3d_scale(viewport_rid, 0.9)
		2:  # High quality - full resolution (scale 1.0 = no scaling, mode doesn't matter when scale is 1.0)
			RenderingServer.viewport_set_scaling_3d_mode(viewport_rid, RenderingServer.VIEWPORT_SCALING_3D_MODE_BILINEAR)
			RenderingServer.viewport_set_scaling_3d_scale(viewport_rid, 1.0)  # Scale of 1.0 = no scaling

func set_target_fps(fps: int):
	target_fps = fps
	Engine.max_fps = fps

func get_current_fps() -> float:
	return current_fps

func get_quality_level() -> int:
	return quality_level

func set_adaptive_quality(enabled: bool):
	adaptive_quality_enabled = enabled
	if not enabled:
		# Reset to high quality when disabled
		quality_level = 2
		apply_quality_settings()
