extends Label

# FPS Counter - Displays current FPS in the top-left corner

func _ready():
	# Position in top-left corner
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 10.0
	offset_top = 10.0
	offset_right = 150.0
	offset_bottom = 40.0
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END
	
	# Style the label
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	
	# Set font size
	var font_size = 20
	add_theme_font_size_override("font_size", font_size)

func _process(_delta):
	# Update FPS display
	var fps = Engine.get_frames_per_second()
	text = "FPS: " + str(fps)

