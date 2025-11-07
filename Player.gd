extends CharacterBody3D

# Player - First-person controller with gamepad support

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003
const GAMEPAD_LOOK_SENSITIVITY = 2.5  # Optimized for Razer Kishi

# Get the gravity from the project settings to be synced with RigidBody nodes
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

const BlockManagerScript := preload("res://BlockManager.gd")

@onready var camera: Camera3D = $Camera3D

const MINE_DISTANCE = 5.0  # Maximum distance to mine blocks

var mouse_captured = false
var terrain_ready = false  # Wait for terrain to be ready before processing physics
var world: Node3D  # Reference to World node
var last_inventory_change_time: float = 0.0
const INVENTORY_CHANGE_COOLDOWN: float = 0.2  # Minimum time between inventory changes (200ms)

func _ready():
	# Capture mouse on start
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true
	
	# Wait for terrain to be ready
	# Try multiple ways to find the World node
	world = get_node_or_null("../World")
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_node_or_null("/root/Main/World")
	
	if world and world.has_signal("terrain_ready"):
		world.terrain_ready.connect(_on_terrain_ready)
	else:
		# Fallback: wait a few frames then enable physics
		await get_tree().create_timer(2.0).timeout
		terrain_ready = true

func _on_terrain_ready():
	terrain_ready = true
	# Ensure player is above ground level - check if we're inside a block
	# If we're inside a block, move up
	if world and world.has_method("get_block_at_position"):
		var block_at_feet = world.get_block_at_position(global_position)
		var block_at_head = world.get_block_at_position(global_position + Vector3(0, 1.6, 0))
		if block_at_feet or block_at_head:
			# Move player up to be above blocks
			global_position.y += 2.0
			print("Player moved up to avoid spawning inside blocks")

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
	
	# Handle mining
	if event.is_action_pressed("mine") and terrain_ready:
		try_mine_block()
	
	# Handle block placement
	if event.is_action_pressed("place") and terrain_ready:
		try_place_block()
	
	# Handle inventory selection (D-pad/arrow keys)
	# Use is_action_just_pressed to prevent repeat triggers and add cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if event.is_action_pressed("inventory_left") and not event.is_echo():
		if current_time - last_inventory_change_time >= INVENTORY_CHANGE_COOLDOWN:
			cycle_inventory_slot(-1)  # Move left in hotbar
			last_inventory_change_time = current_time
	if event.is_action_pressed("inventory_right") and not event.is_echo():
		if current_time - last_inventory_change_time >= INVENTORY_CHANGE_COOLDOWN:
			cycle_inventory_slot(1)  # Move right in hotbar
			last_inventory_change_time = current_time

func _physics_process(delta):
	# CRITICAL: Don't process physics until terrain is ready
	if not terrain_ready:
		return
	
	# Also check for mining/placement in physics process for better gamepad support
	if Input.is_action_just_pressed("mine"):
		try_mine_block()
	if Input.is_action_just_pressed("place"):
		try_place_block()
	
	# Also check for inventory navigation in physics process for better gamepad support
	# Use is_action_just_pressed to prevent repeat triggers and add cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if Input.is_action_just_pressed("inventory_left"):
		if current_time - last_inventory_change_time >= INVENTORY_CHANGE_COOLDOWN:
			cycle_inventory_slot(-1)  # Move left in hotbar
			last_inventory_change_time = current_time
	if Input.is_action_just_pressed("inventory_right"):
		if current_time - last_inventory_change_time >= INVENTORY_CHANGE_COOLDOWN:
			cycle_inventory_slot(1)  # Move right in hotbar
			last_inventory_change_time = current_time
	
	# Note: Trigger axes are now handled in input map (axis 6 for L2, axis 7 for R2)
	# This ensures proper support for Razer Edge controller triggers
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
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
	move_and_slide()

func get_targeted_block() -> Dictionary:
	# Raycast from camera to detect block
	if not camera or not terrain_ready:
		return {}
	
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var forward = -camera.global_transform.basis.z
	var to = from + forward * MINE_DISTANCE
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # Blocks are on layer 1
	query.exclude = [self]  # Don't hit player
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.get("collider")
		var hit_position = result.get("position")
		var normal = result.get("normal")
		
		# Skip mining effects (they shouldn't have collision, but just in case)
		if collider and collider.name.begins_with("MiningEffect_"):
			return {}
		
		if collider is StaticBody3D:
			# Verify this is actually a block (has block_type metadata or name starts with "Block_")
			var is_block = false
			if collider.has_meta("block_type"):
				is_block = true
			elif collider.name.begins_with("Block_"):
				is_block = true
			
			if is_block:
				return {
					"block": collider,
					"position": collider.global_position,
					"hit_position": hit_position,
					"normal": normal
				}
	
	return {}

func try_mine_block():
	var target = get_targeted_block()
	if target.is_empty():
		return
	
	var block_pos = target["position"]
	
	# Check distance
	var distance = camera.global_position.distance_to(block_pos)
	if distance > MINE_DISTANCE:
		return
	
	# Get block type from block metadata or name
	var block = target["block"] as StaticBody3D
	if not block:
		return
	
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		return
	
	# Try to get block type from metadata first
	var block_type = null
	if block.has_meta("block_type"):
		block_type = block.get_meta("block_type")
	else:
		# Fallback to name parsing
		var block_name = block.name
		block_type = inventory.get_block_type_from_name(block_name)
	
	if block_type == null:
		return
	
	# Check if block is bedrock (not mineable)
	if block_type == BlockManagerScript.BlockType.BEDROCK:
		# Bedrock cannot be mined
		return
	
	# Round position to match how blocks are stored
	var rounded_pos = Vector3(
		round(block_pos.x),
		round(block_pos.y),
		round(block_pos.z)
	)
	
	# Remove block from world FIRST, then create effect
	if world and world.has_method("remove_block"):
		if world.remove_block(rounded_pos):
			# Create mining effect (visual: shrink and spin)
			create_mining_effect(block_type, block_pos)

func create_mining_effect(block_type: BlockManagerScript.BlockType, position: Vector3):
	# Create a mining effect node
	var effect = Node3D.new()
	var script = load("res://MiningEffect.gd")
	effect.set_script(script)
	effect.block_type = block_type
	effect.target_position = position
	# Offset slightly upward to prevent visual overlap with ground
	effect.global_position = position + Vector3(0, 0.1, 0)
	effect.name = "MiningEffect_" + str(block_type)
	
	# Note: Node3D doesn't have collision_layer/mask properties
	# All physics bodies are removed in MiningEffect.gd, so no collision exists
	
	# Add to world or main scene
	if world:
		world.add_child(effect)
	else:
		get_tree().root.add_child(effect)

func try_place_block():
	var target = get_targeted_block()
	if target.is_empty():
		print("DEBUG: No target block for placement")
		return
	
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		print("DEBUG: No inventory found")
		return
	
	var selected_item = inventory.get_selected_item()
	if selected_item["type"] == null or selected_item["count"] <= 0:
		print("DEBUG: No item selected or count is 0")
		return
	
	# Get the block's position (center of the block)
	var block_pos = target["position"]
	var normal = target["normal"]
	
	# Calculate placement position: place adjacent to the face we're looking at
	# The normal points away from the block, so we add it to place the block next to it
	# Since blocks are 1x1x1, we add the normal (which is normalized) to get the adjacent position
	var placement_pos = block_pos + normal
	
	# Snap to grid (blocks are at integer positions)
	placement_pos = Vector3(
		round(placement_pos.x),
		round(placement_pos.y),
		round(placement_pos.z)
	)
	
	print("DEBUG: Trying to place block at ", placement_pos, " (block at ", block_pos, ", normal: ", normal, ")")
	
	# Check if placement position is too close to player (prevent placing inside player)
	var player_bottom = global_position + Vector3(0, -0.9, 0)  # Bottom of player capsule
	var player_top = global_position + Vector3(0, 1.8, 0)  # Top of player capsule
	
	if placement_pos.y >= player_bottom.y - 0.5 and placement_pos.y <= player_top.y + 0.5:
		# Check horizontal distance
		var horizontal_dist = Vector2(placement_pos.x, placement_pos.z).distance_to(Vector2(global_position.x, global_position.z))
		if horizontal_dist < 0.6:  # Player radius is 0.4, add some margin
			print("DEBUG: Placement position too close to player")
			return
	
	# Place block
	if world and world.has_method("place_block"):
		var success = world.place_block(selected_item["type"], placement_pos)
		print("DEBUG: place_block returned: ", success)
		if success:
			# Remove from inventory
			inventory.remove_item(inventory.selected_slot, 1)
			print("DEBUG: Block placed successfully")
		else:
			print("DEBUG: Block placement failed")

func cycle_inventory_slot(direction: int):
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		return
	
	# Direction: positive moves right (forward), negative moves left (backward)
	var new_slot = inventory.selected_slot + direction
	
	# Wrap around: if going left from slot 0, go to slot 8; if going right from slot 8, go to slot 0
	if new_slot < 0:
		new_slot = 8
	elif new_slot >= 9:
		new_slot = 0
	
	inventory.set_selected_slot(new_slot)
	# Removed debug print to reduce console spam

