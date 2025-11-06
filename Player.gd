extends CharacterBody3D

# Player - First-person controller with gamepad support

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003
const GAMEPAD_LOOK_SENSITIVITY = 2.0

# Get the gravity from the project settings to be synced with RigidBody nodes
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera: Camera3D = $Camera3D

var mouse_captured = false
var terrain_ready = false  # Wait for terrain to be ready before processing physics

func _ready():
	# Capture mouse on start
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true
	
	# Wait for terrain to be ready
	# Try multiple ways to find the World node
	var world = get_node_or_null("../World")
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_node_or_null("/root/Main/World")
	
	if world and world.has_signal("terrain_ready"):
		world.terrain_ready.connect(_on_terrain_ready)
		print("Player waiting for terrain to be ready...")
	else:
		# Fallback: wait a few frames then enable physics
		print("WARNING: Could not find World node, enabling physics after delay")
		await get_tree().create_timer(2.0).timeout
		terrain_ready = true

func _on_terrain_ready():
	terrain_ready = true
	print("Player: Terrain ready! Physics enabled.")

func _input(event):
	# Handle mouse capture toggle
	if event.is_action_pressed("ui_cancel"):
		if mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			mouse_captured = false
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			mouse_captured = true
	
	# Handle mouse look
	if event is InputEventMouseMotion and mouse_captured:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		# Clamp camera rotation to prevent flipping
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _physics_process(delta):
	# CRITICAL: Don't process physics until terrain is ready
	if not terrain_ready:
		return
	
	# Debug: Check if we're on floor
	if not is_on_floor():
		velocity.y -= gravity * delta
		# Debug output every 60 frames
		if Engine.get_physics_frames() % 60 == 0:
			print("Player falling - Position: ", position, " Velocity: ", velocity, " On floor: ", is_on_floor())
	
	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Get input direction
	var input_dir = Vector2()
	
	# Keyboard input
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_back"):
		input_dir.y += 1
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1
	
	# Gamepad input (left stick for movement)
	var gamepad_move = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)
	
	# Combine keyboard and gamepad input (gamepad takes priority if active)
	if gamepad_move.length() > 0.1:
		input_dir = gamepad_move
	
	# Gamepad camera look (right stick) - check all connected gamepads
	var gamepad_look = Vector2()
	for device_id in Input.get_connected_joypads():
		var look_x = Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X)
		var look_y = Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		if abs(look_x) > 0.1 or abs(look_y) > 0.1:
			gamepad_look = Vector2(look_x, look_y)
			break
	
	# Fallback to action-based input if no direct axis input
	if gamepad_look.length() < 0.1:
		gamepad_look = Vector2(
			Input.get_axis("look_left", "look_right"),
			Input.get_axis("look_up", "look_down")
		)
	
	if gamepad_look.length() > 0.1:
		rotate_y(-gamepad_look.x * GAMEPAD_LOOK_SENSITIVITY * delta)
		camera.rotate_x(-gamepad_look.y * GAMEPAD_LOOK_SENSITIVITY * delta)
		# Clamp camera rotation
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
	# Normalize input direction and apply movement
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
	
	# Get the direction relative to where the player is looking
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	
	# Use move_and_slide with explicit parameters
	# max_slides=6 is default, but let's be explicit
	# floor_max_angle=0.785398 is ~45 degrees (default)
	# floor_snap_length=0.0 means no snapping
	var was_on_floor = is_on_floor()
	move_and_slide()
	
	# Debug: Check if we're colliding after movement
	if not was_on_floor and is_on_floor():
		print("SUCCESS: Player landed on floor!")
	
	# Debug collision info
	if Engine.get_physics_frames() % 60 == 0 and not is_on_floor():
		# Check get_last_slide_collision
		var last_collision = get_last_slide_collision()
		if last_collision:
			print("Last slide collision: ", last_collision.get_collider(), " Normal: ", last_collision.get_normal())
		else:
			print("No slide collision detected")
	
	# Debug: Check collision after movement
	if Engine.get_physics_frames() % 60 == 0 and not is_on_floor():
		# Try multiple raycasts to debug
		var space_state = get_world_3d().direct_space_state
		
		# Raycast straight down
		var query_down = PhysicsRayQueryParameters3D.create(position, position + Vector3.DOWN * 10.0)
		query_down.collision_mask = 1
		var result_down = space_state.intersect_ray(query_down)
		
		# Raycast to block at (32, 0, 32)
		var block_pos = Vector3(32, 0.5, 32)
		var query_block = PhysicsRayQueryParameters3D.create(position, block_pos)
		query_block.collision_mask = 1
		var result_block = space_state.intersect_ray(query_block)
		
		if result_down:
			print("Raycast DOWN hit: ", result_down.get("collider"), " at: ", result_down.position)
		elif result_block:
			print("Raycast to block hit: ", result_block.get("collider"), " at: ", result_block.position)
		else:
			print("Raycast found NO collision. Player at: ", position, " Block should be at: (32, 0, 32)")

