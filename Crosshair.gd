extends Control

# Crosshair - Simple centered crosshair for targeting blocks

@onready var crosshair_line_top: Line2D = $CrosshairLineTop
@onready var crosshair_line_bottom: Line2D = $CrosshairLineBottom
@onready var crosshair_line_left: Line2D = $CrosshairLineLeft
@onready var crosshair_line_right: Line2D = $CrosshairLineRight

const CROSSHAIR_SIZE = 8.0
const CROSSHAIR_GAP = 4.0
const CROSSHAIR_COLOR = Color.WHITE

func _ready():
	# Wait for next frame to ensure @onready variables are initialized
	await get_tree().process_frame
	setup_crosshair()

func setup_crosshair():
	# Ensure nodes are available
	if not crosshair_line_top or not crosshair_line_bottom or not crosshair_line_left or not crosshair_line_right:
		# Try to get nodes manually if @onready failed
		crosshair_line_top = get_node_or_null("CrosshairLineTop")
		crosshair_line_bottom = get_node_or_null("CrosshairLineBottom")
		crosshair_line_left = get_node_or_null("CrosshairLineLeft")
		crosshair_line_right = get_node_or_null("CrosshairLineRight")
		
		if not crosshair_line_top or not crosshair_line_bottom or not crosshair_line_left or not crosshair_line_right:
			return
	
	# Center the crosshair
	var viewport_size = get_viewport_rect().size
	var center_x = viewport_size.x / 2.0
	var center_y = viewport_size.y / 2.0
	
	# Clear existing points
	crosshair_line_top.clear_points()
	crosshair_line_bottom.clear_points()
	crosshair_line_left.clear_points()
	crosshair_line_right.clear_points()
	
	# Top line
	crosshair_line_top.add_point(Vector2(center_x, center_y - CROSSHAIR_GAP))
	crosshair_line_top.add_point(Vector2(center_x, center_y - CROSSHAIR_GAP - CROSSHAIR_SIZE))
	crosshair_line_top.default_color = CROSSHAIR_COLOR
	crosshair_line_top.width = 2.0
	
	# Bottom line
	crosshair_line_bottom.add_point(Vector2(center_x, center_y + CROSSHAIR_GAP))
	crosshair_line_bottom.add_point(Vector2(center_x, center_y + CROSSHAIR_GAP + CROSSHAIR_SIZE))
	crosshair_line_bottom.default_color = CROSSHAIR_COLOR
	crosshair_line_bottom.width = 2.0
	
	# Left line
	crosshair_line_left.add_point(Vector2(center_x - CROSSHAIR_GAP, center_y))
	crosshair_line_left.add_point(Vector2(center_x - CROSSHAIR_GAP - CROSSHAIR_SIZE, center_y))
	crosshair_line_left.default_color = CROSSHAIR_COLOR
	crosshair_line_left.width = 2.0
	
	# Right line
	crosshair_line_right.add_point(Vector2(center_x + CROSSHAIR_GAP, center_y))
	crosshair_line_right.add_point(Vector2(center_x + CROSSHAIR_GAP + CROSSHAIR_SIZE, center_y))
	crosshair_line_right.default_color = CROSSHAIR_COLOR
	crosshair_line_right.width = 2.0

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		# Re-center crosshair on resize
		setup_crosshair()
