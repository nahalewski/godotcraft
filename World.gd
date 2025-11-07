extends Node3D

# World - Generates Minecraft-like terrain with height variation and caves
# Supports infinite terrain generation with chunk-based loading

const CHUNK_SIZE = 16  # Size of each chunk (16x16 blocks)
const MAP_SIZE = 64  # Initial map size (will be expanded dynamically)
const BLOCK_SIZE = 1.0  # Size of each block in world units
const MAX_HEIGHT = 32  # Maximum terrain height
const MIN_HEIGHT = 0   # Minimum terrain height (sea level)
const BEDROCK_LAYER = 3  # Number of bedrock layers at bottom
var GENERATION_DISTANCE = 1  # Generate chunks this many chunks away from player (reduced for performance)
const INITIAL_GENERATION_DISTANCE = 0  # Start with just 1 chunk for fastest loading

const BlockManagerScript := preload("res://BlockManager.gd")

# Performance settings
const BLOCKS_PER_FRAME = 100  # Increased for faster generation
const SURFACE_BLOCKS_PER_FRAME = 200  # Generate surface blocks faster (player needs these first)
const VEGETATION_BATCH_SIZE = 50  # Process vegetation in larger batches

@export var block_spacing: float = 1.0
@export var terrain_noise_scale: float = 0.1  # Controls terrain smoothness
@export var terrain_height_multiplier: float = 10.0  # Height variation amount (reduced for performance)
@export var cave_threshold: float = 0.3  # Lower = more caves (0.0 to 1.0)
@export var cave_noise_scale: float = 0.15  # Cave size

# Signal emitted when terrain generation is complete and physics is ready
signal terrain_ready

# Track all blocks for efficient lookup
var blocks_by_position: Dictionary = {}
var blocks_container: Node3D

var block_manager: Node  # BlockManager autoload singleton

# Track which chunks have been generated (chunk coordinates)
var generated_chunks: Dictionary = {}  # Key: Vector2i(chunk_x, chunk_z), Value: true

# Track chunks currently being generated to prevent race conditions
var generating_chunks: Dictionary = {}  # Key: Vector2i(chunk_x, chunk_z), Value: true

# Cleanup tracking to prevent excessive cleanup calls
var cleanup_call_count: int = 0
var last_cleanup_time: float = 0.0
const CLEANUP_COOLDOWN: float = 5.0  # Minimum seconds between cleanup calls

# Performance optimization settings
var merge_block_meshes: bool = false  # Merge blocks into chunk meshes
var chunk_physics_only: bool = false  # One physics body per chunk
var use_multimesh_vegetation: bool = false  # Use MultiMesh for vegetation
var face_culling_enabled: bool = true  # Cull hidden block faces

# Track chunk mesh nodes (when mesh merging is enabled)
var chunk_meshes: Dictionary = {}  # Key: Vector2i(chunk_x, chunk_z), Value: MeshInstance3D
var chunk_physics_bodies: Dictionary = {}  # Key: Vector2i(chunk_x, chunk_z), Value: StaticBody3D

# Track chunk block data (for mesh merging)
var chunk_block_data: Dictionary = {}  # Key: Vector2i(chunk_x, chunk_z), Value: Dictionary{Vector3i: BlockType}

# MultiMesh vegetation tracking
var multimesh_trees: MultiMeshInstance3D = null
var multimesh_bushes: MultiMeshInstance3D = null
var multimesh_tree_transforms: Array[Transform3D] = []
var multimesh_bush_transforms: Array[Transform3D] = []
var multimesh_tree_models: Array = []
var multimesh_bush_models: Array = []

# Reference to player for position tracking
var player: CharacterBody3D

# Noise generators for terrain and caves
var terrain_noise: FastNoiseLite
var cave_noise: FastNoiseLite
var vegetation_noise: FastNoiseLite  # For random tree/bush placement

# Vegetation settings
@export var tree_chance: float = 0.05  # 5% base chance for tree on grass blocks (increased from 2% for better visibility)
@export var bush_chance: float = 0.10  # 10% base chance for bush on grass blocks (increased from 5% for better visibility)

# Track vegetation positions to avoid duplicates
var vegetation_positions: Dictionary = {}  # Key: Vector2i(x, z), Value: true

# Vegetation model lists
var tree_models: PackedStringArray = [
	"Tree_1_A_Color1", "Tree_1_B_Color1", "Tree_1_C_Color1",
	"Tree_2_A_Color1", "Tree_2_B_Color1", "Tree_2_C_Color1", "Tree_2_D_Color1", "Tree_2_E_Color1",
	"Tree_3_A_Color1", "Tree_3_B_Color1", "Tree_3_C_Color1",
	"Tree_4_A_Color1", "Tree_4_B_Color1", "Tree_4_C_Color1"
]

var bush_models: PackedStringArray = [
	"Bush_1_A_Color1", "Bush_1_B_Color1", "Bush_1_C_Color1", "Bush_1_D_Color1", "Bush_1_E_Color1", "Bush_1_F_Color1", "Bush_1_G_Color1",
	"Bush_2_A_Color1", "Bush_2_B_Color1", "Bush_2_C_Color1", "Bush_2_D_Color1", "Bush_2_E_Color1", "Bush_2_F_Color1",
	"Bush_3_A_Color1", "Bush_3_B_Color1", "Bush_3_C_Color1",
	"Bush_4_A_Color1", "Bush_4_B_Color1", "Bush_4_C_Color1", "Bush_4_D_Color1", "Bush_4_E_Color1", "Bush_4_F_Color1"
]

# ------------------ GRID HELPERS (single source of truth) ------------------
func to_grid_key_from_world(pos: Vector3) -> Vector3i:
	# Convert a world-space position to integer grid coordinates using floor on floats
	var gx := int(floor(pos.x / BLOCK_SIZE))
	var gy := int(floor(pos.y / BLOCK_SIZE))
	var gz := int(floor(pos.z / BLOCK_SIZE))
	return Vector3i(gx, gy, gz)

func to_world_from_grid(key: Vector3i) -> Vector3:
	# Convert integer grid coordinates back to world-space position
	return Vector3(key.x * BLOCK_SIZE, key.y * BLOCK_SIZE, key.z * BLOCK_SIZE)

func _ready():
	# Enable VSync on desktop to prevent screen tearing (Android handled separately)
	if OS.get_name() != "Android":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	
	# Get BlockManager autoload singleton (available after scene tree is ready)
	block_manager = get_node_or_null("/root/BlockManager")
	if not block_manager:
		push_error("BlockManager autoload not found! Block generation will fail.")
		return
	
	# Load render distance and performance settings from settings
	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager:
		GENERATION_DISTANCE = settings_manager.max_render_distance
		merge_block_meshes = settings_manager.merge_block_meshes
		chunk_physics_only = settings_manager.chunk_physics_only
		use_multimesh_vegetation = settings_manager.use_multimesh_vegetation
		face_culling_enabled = settings_manager.face_culling
		add_to_group("world")  # Add to group so SettingsManager can find us
	
	# Initialize noise generators
	terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = randi()
	terrain_noise.frequency = terrain_noise_scale
	terrain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	cave_noise = FastNoiseLite.new()
	cave_noise.seed = randi() + 1000  # Different seed for caves
	cave_noise.frequency = cave_noise_scale
	cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# Initialize vegetation noise for random placement
	vegetation_noise = FastNoiseLite.new()
	vegetation_noise.seed = randi() + 2000  # Different seed for vegetation
	vegetation_noise.frequency = 0.1  # Low frequency for smooth distribution
	vegetation_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# Find player reference
	player = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_node_or_null("../Player")
	
	# Generate initial terrain
	generate_terrain()
	
	# Start checking for new chunks to generate
	check_and_generate_chunks()

func generate_terrain():
	print("Generating initial Minecraft-like terrain with caves...")
	
	# Create a parent node for all blocks to keep hierarchy clean
	if not blocks_container:
		blocks_container = Node3D.new()
		blocks_container.name = "Blocks"
		# CRITICAL: Ensure blocks_container is at origin with no transform
		# This ensures block positions match their global positions exactly
		blocks_container.position = Vector3.ZERO
		blocks_container.rotation = Vector3.ZERO
		blocks_container.scale = Vector3.ONE
		blocks_container.transform = Transform3D.IDENTITY
		add_child(blocks_container)
	
	# Create a parent node for all vegetation (trees and bushes)
	var vegetation_container = get_node_or_null("Vegetation")
	if not vegetation_container:
		vegetation_container = Node3D.new()
		vegetation_container.name = "Vegetation"
		# CRITICAL: Ensure vegetation_container is at origin with no transform
		vegetation_container.position = Vector3.ZERO
		vegetation_container.rotation = Vector3.ZERO
		vegetation_container.scale = Vector3.ONE
		vegetation_container.transform = Transform3D.IDENTITY
		add_child(vegetation_container)
	
	# Generate fewer initial chunks for faster loading
	var initial_chunks = INITIAL_GENERATION_DISTANCE
	for chunk_x in range(-initial_chunks, initial_chunks + 1):
		for chunk_z in range(-initial_chunks, initial_chunks + 1):
			generate_chunk(chunk_x, chunk_z)
			# Yield every chunk to keep loading responsive
			await get_tree().process_frame
	
	print("Initial terrain generation complete!")
	
	# Clean up any duplicate blocks before setting up collision (only once after initial generation)
	cleanup_duplicate_blocks()
	
	# Set up collision and emit ready signal (async)
	setup_collision_and_ready()
	
	# Place vegetation asynchronously after terrain is ready (doesn't block player)
	place_initial_vegetation()

func generate_chunk(chunk_x: int, chunk_z: int) -> void:
	# Convert to chunk key and ensure we're not regenerating the same area
	var chunk_key = Vector2i(chunk_x, chunk_z)
	if generated_chunks.has(chunk_key) or generating_chunks.has(chunk_key):
		return
	
	generating_chunks[chunk_key] = true
	
	var generation_failed := false
	
	# Define where this chunk begins in world coordinates
	var world_start_x := chunk_x * CHUNK_SIZE
	var world_start_z := chunk_z * CHUNK_SIZE
	
	# --- PASS 1: precompute surface heights ---
	var surface_heights := {}
	for local_x in range(CHUNK_SIZE):
		for local_z in range(CHUNK_SIZE):
			var world_x := world_start_x + local_x
			var world_z := world_start_z + local_z
			
			var noise_value := terrain_noise.get_noise_2d(world_x, world_z)
			var height := int((noise_value + 1.0) * 0.5 * terrain_height_multiplier) + MIN_HEIGHT
			height = clamp(height, MIN_HEIGHT, MAX_HEIGHT)
			surface_heights[Vector2i(world_x, world_z)] = height
	
	# --- PASS 2: Collect block data or instantiate blocks ---
	var chunk_block_data_local: Dictionary = {}  # Store block data for mesh merging
	
	var blocks_created := 0
	var surface_blocks_created := 0
	
	# FIRST: Generate surface blocks (player needs these for collision)
	# Generate from top to bottom so surface is ready first
	for local_x in range(CHUNK_SIZE):
		for local_z in range(CHUNK_SIZE):
			var world_x := world_start_x + local_x
			var world_z := world_start_z + local_z
			var surface_height: int = surface_heights[Vector2i(world_x, world_z)]
			
			# Generate from surface downward (faster collision)
			for y in range(surface_height, -1, -1):  # Start from surface, go down
				if should_be_cave(world_x, y, world_z, surface_height):
					continue
				
				var block_type := get_block_type_for_height(y, surface_height)
				var pos_key := Vector3i(world_x, y, world_z)
				var exact_position := to_world_from_grid(pos_key)
				
				# Store block data for mesh merging
				if merge_block_meshes:
					chunk_block_data_local[pos_key] = block_type
					# Mark position as having a block (for face culling) - use true as marker
					blocks_by_position[pos_key] = true
					continue  # Skip individual block instantiation when mesh merging
				
				# --- ATOMIC: Check and skip if already placed (prevents race conditions) ---
				if blocks_by_position.has(pos_key):
					var existing = blocks_by_position[pos_key]
					if existing and is_instance_valid(existing) and existing.is_inside_tree():
						var existing_key = to_grid_key_from_world(existing.global_position)
						if existing_key == pos_key:
							continue
						else:
							blocks_by_position.erase(pos_key)
				
				# Double-check scene tree
				var block_name = "Block_%d_%d_%d" % [world_x, y, world_z]
				var existing_node = blocks_container.get_node_or_null(block_name)
				if existing_node and is_instance_valid(existing_node) and existing_node.is_inside_tree():
					var existing_key = to_grid_key_from_world(existing_node.global_position)
					if existing_key == pos_key:
						blocks_by_position[pos_key] = existing_node as StaticBody3D
						continue
				
				# --- instantiate block (using fast template duplication) ---
				if not block_manager:
					generation_failed = true
					continue
				
				var static_body: StaticBody3D = null
				if block_manager.has_method("get_block_fast"):
					static_body = block_manager.get_block_fast(block_type, exact_position)
				else:
					var block_instance: Node3D = block_manager.get_block_instance(block_type)
					if block_instance == null:
						generation_failed = true
						continue
					block_instance.name = block_name
					block_instance.set_meta("block_type", block_type)
					static_body = block_manager.create_block_with_physics(block_instance, exact_position)
				
				if static_body == null:
					generation_failed = true
					continue
				
				static_body.name = block_name
				static_body.set_meta("block_type", block_type)
				
				# ATOMIC: Add to dictionary BEFORE adding to scene
				blocks_by_position[pos_key] = static_body
				
				# Add to scene
				blocks_container.add_child(static_body)
				static_body.owner = blocks_container
				
				# Place exactly on grid
				static_body.position = exact_position
				
				# Verify position after adding
				if static_body.is_inside_tree():
					var actual_global = static_body.global_position
					var expected_global = exact_position
					if not actual_global.is_equal_approx(expected_global):
						static_body.position = exact_position
						static_body.set_notify_transform(true)
				
				if block_manager:
					block_manager.ensure_block_collision(static_body)
				static_body.collision_layer = 1
				static_body.collision_mask = 0
				
				blocks_created += 1
				# Surface blocks (y == surface_height) get priority - yield less frequently
				if y == surface_height:
					surface_blocks_created += 1
					if surface_blocks_created % SURFACE_BLOCKS_PER_FRAME == 0:
						await get_tree().process_frame
				else:
					# Underground blocks can yield more frequently
					if blocks_created % BLOCKS_PER_FRAME == 0:
						await get_tree().process_frame
	
	# If mesh merging is enabled, create merged mesh for this chunk
	if merge_block_meshes and not chunk_block_data_local.is_empty():
		chunk_block_data[chunk_key] = chunk_block_data_local
		
		# Update blocks_by_position to use actual markers (for face culling)
		# Use the block data to mark positions
		for pos_key in chunk_block_data_local.keys():
			blocks_by_position[pos_key] = true  # Use true as marker for merged mesh blocks
		
		# Create merged mesh and physics
		var mesh_instance = create_chunk_mesh_node(chunk_x, chunk_z)
		if mesh_instance:
			blocks_container.add_child(mesh_instance)
			mesh_instance.owner = blocks_container
			chunk_meshes[chunk_key] = mesh_instance
			
			# Create chunk physics body (if chunk_physics_only is enabled or mesh merging is enabled)
			if chunk_physics_only or merge_block_meshes:
				var physics_body = create_chunk_physics_body(chunk_x, chunk_z)
				if physics_body:
					blocks_container.add_child(physics_body)
					physics_body.owner = blocks_container
					chunk_physics_bodies[chunk_key] = physics_body
	
	generating_chunks.erase(chunk_key)
	if not generation_failed:
		generated_chunks[chunk_key] = true

func get_chunk_coords(world_pos: Vector3) -> Vector2i:
	# Convert world position (units) to chunk coordinates (x,z)
	var units_per_chunk := float(CHUNK_SIZE) * BLOCK_SIZE
	var cx := int(floor(world_pos.x / units_per_chunk))
	var cz := int(floor(world_pos.z / units_per_chunk))
	return Vector2i(cx, cz)

# Track last player chunk to only generate when player moves to new chunk
var last_player_chunk: Vector2i = Vector2i(0, 0)

func check_and_generate_chunks():
	# Continuously check and generate chunks around player
	while true:
		if not player or not is_instance_valid(player):
			await get_tree().create_timer(1.0).timeout
			continue
		
		var player_pos = player.global_position
		var player_chunk = get_chunk_coords(player_pos)
		
		# Generate chunks in a square around the player
		var chunks_to_generate = []
		for chunk_x in range(player_chunk.x - GENERATION_DISTANCE, player_chunk.x + GENERATION_DISTANCE + 1):
			for chunk_z in range(player_chunk.y - GENERATION_DISTANCE, player_chunk.y + GENERATION_DISTANCE + 1):
				var chunk_key = Vector2i(chunk_x, chunk_z)
				# Check if chunk is already generated or currently being generated
				if not generated_chunks.has(chunk_key) and not generating_chunks.has(chunk_key):
					chunks_to_generate.append(Vector2i(chunk_x, chunk_z))
		
		# Only generate and cleanup if there are chunks to generate (optimization)
		if chunks_to_generate.size() > 0:
			# PRIORITY: Generate player's current chunk first to prevent falling through
			var player_chunk_key = Vector2i(player_chunk.x, player_chunk.y)
			var player_chunk_priority = null
			var other_chunks = []
			
			for chunk_coords in chunks_to_generate:
				if Vector2i(chunk_coords.x, chunk_coords.y) == player_chunk_key:
					player_chunk_priority = chunk_coords
				else:
					other_chunks.append(chunk_coords)
			
			# Generate player's chunk FIRST (highest priority)
			if player_chunk_priority != null:
				generate_chunk(player_chunk_priority.x, player_chunk_priority.y)
				# Wait one frame for physics to register surface blocks
				await get_tree().physics_frame
			
			# Then generate other chunks
			for chunk_coords in other_chunks:
				generate_chunk(chunk_coords.x, chunk_coords.y)
				
				# Place vegetation for this newly generated chunk
				# Calculate surface heights for vegetation placement
				var world_start_x = chunk_coords.x * CHUNK_SIZE
				var world_start_z = chunk_coords.y * CHUNK_SIZE
				var surface_heights = {}
				for x in range(world_start_x, world_start_x + CHUNK_SIZE):
					for z in range(world_start_z, world_start_z + CHUNK_SIZE):
						var noise_value = terrain_noise.get_noise_2d(x, z)
						var height = int((noise_value + 1.0) * 0.5 * terrain_height_multiplier) + MIN_HEIGHT
						height = clamp(height, MIN_HEIGHT, MAX_HEIGHT)
						surface_heights[Vector2i(x, z)] = height
				
				# Place vegetation asynchronously (lower priority - can be deferred)
				place_vegetation_for_chunk(chunk_coords.x, chunk_coords.y, surface_heights)  # Don't await - let it run in background
				
				# Yield less frequently between chunks for faster generation
				await get_tree().process_frame
			
			# Also generate vegetation for player's chunk (if it was generated)
			if player_chunk_priority != null:
				var world_start_x = player_chunk_priority.x * CHUNK_SIZE
				var world_start_z = player_chunk_priority.y * CHUNK_SIZE
				var surface_heights = {}
				for x in range(world_start_x, world_start_x + CHUNK_SIZE):
					for z in range(world_start_z, world_start_z + CHUNK_SIZE):
						var noise_value = terrain_noise.get_noise_2d(x, z)
						var height = int((noise_value + 1.0) * 0.5 * terrain_height_multiplier) + MIN_HEIGHT
						height = clamp(height, MIN_HEIGHT, MAX_HEIGHT)
						surface_heights[Vector2i(x, z)] = height
				place_vegetation_for_chunk(player_chunk_priority.x, player_chunk_priority.y, surface_heights)  # Background task
			
			# Only run cleanup when new chunks were generated and with longer cooldown
			var current_time = Time.get_ticks_msec() / 1000.0
			if (current_time - last_cleanup_time) >= 5.0:  # Reduced frequency: every 5 seconds
				cleanup_duplicate_blocks_optimized()
				last_cleanup_time = current_time
		
		# Update last player chunk
		last_player_chunk = player_chunk
		
		# Wait before checking again (shorter wait when generating to keep up with player)
		if chunks_to_generate.size() > 0:
			# If generating chunks, check again very soon to catch up quickly
			await get_tree().create_timer(0.1).timeout
		else:
			# If no chunks to generate, wait longer (player in already-generated area)
			await get_tree().create_timer(1.0).timeout

func setup_collision_and_ready():
	# Verify all blocks have collision (some may have been set up during generation)
	print("Verifying block collision shapes...")
	var blocks_processed = 0
	var blocks_without_collision = 0
	var batch_size = 500  # Larger batches for faster processing
	
	for pos_key in blocks_by_position:
		var block = blocks_by_position[pos_key]
		if block and is_instance_valid(block):
			# Ensure collision layer is set
			block.collision_layer = 1
			block.collision_mask = 0
			
			# Check if collision exists
			var has_collision = false
			for child in block.get_children():
				if child is CollisionShape3D and child.shape != null:
					has_collision = true
					break
			
			if not has_collision:
				blocks_without_collision += 1
				if block_manager:
					block_manager.ensure_block_collision(block)
				block.collision_layer = 1
				block.collision_mask = 0
			
			blocks_processed += 1
			# Yield more frequently to keep FPS up
			if blocks_processed % batch_size == 0:
				await get_tree().process_frame
	
	if blocks_without_collision > 0:
		print("Added collision shapes to ", blocks_without_collision, " blocks")
	
	# CRITICAL: Wait for physics server to register all collision shapes
	# This is essential to prevent falling through blocks
	print("Waiting for physics server to register collision shapes...")
	# Reduced physics frame waits - 2 frames should be enough
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Signal terrain ready
	terrain_ready.emit()
	print("Terrain ready signal emitted - player can now move!")
	
	# Start background music
	var music_player = get_node_or_null("BackgroundMusic")
	if music_player:
		music_player.play()

func should_be_cave(x: int, y: int, z: int, surface_height: int) -> bool:
	# Don't create caves near the surface (keep at least 3 blocks below surface)
	if y >= surface_height - 3:
		return false
	
	# Don't create caves in bedrock layer
	if y < BEDROCK_LAYER:
		return false
	
	# Use 3D noise for cave generation
	var cave_noise_value = cave_noise.get_noise_3d(x, y, z)
	# Normalize from -1..1 to 0..1
	var normalized_cave = (cave_noise_value + 1.0) * 0.5
	
	# If noise is below threshold, it's a cave (air)
	return normalized_cave < cave_threshold

func get_block_type_for_height(y: int, surface_height: int) -> BlockManagerScript.BlockType:
	# Bedrock layer at bottom (not mineable)
	if y < BEDROCK_LAYER:
		return BlockManagerScript.BlockType.BEDROCK
	
	# Surface layer: grass (topmost block)
	if y == surface_height:
		return BlockManagerScript.BlockType.GRASS
	
	# Just below surface: dirt (topsoil layer, 3 blocks deep)
	if y < surface_height and y >= surface_height - 3:
		return BlockManagerScript.BlockType.DIRT
	
	# Deep underground: stone
	return BlockManagerScript.BlockType.STONE

func remove_block(position: Vector3) -> bool:
	var pos_key := to_grid_key_from_world(position)
	
	# Check if block exists
	if not blocks_by_position.has(pos_key):
		return false
	
	var block = blocks_by_position[pos_key]
	if block and is_instance_valid(block):
		# Check if block is bedrock (not mineable)
		if block.has_meta("block_type"):
			var block_type = block.get_meta("block_type")
			if block_type == BlockManagerScript.BlockType.BEDROCK:
				# Bedrock cannot be mined
				return false
		
		# Remove from tracking FIRST
		blocks_by_position.erase(pos_key)
		
		# Remove from scene
		if block.get_parent():
			block.get_parent().remove_child(block)
		block.queue_free()
		return true
	
	return false

func place_block(block_type: BlockManagerScript.BlockType, position: Vector3) -> bool:
	var pos_key := to_grid_key_from_world(position)
	var exact_position := to_world_from_grid(pos_key)
	
	# ATOMIC: Check if position is already occupied (verify in both dictionary and scene tree)
	if blocks_by_position.has(pos_key):
		var existing_block = blocks_by_position[pos_key]
		if existing_block and is_instance_valid(existing_block) and existing_block.is_inside_tree():
			# Verify it's actually at this position
			var existing_key = to_grid_key_from_world(existing_block.global_position)
			if existing_key == pos_key:
				return false
			else:
				# Block is at wrong position - remove from dictionary
				blocks_by_position.erase(pos_key)
	
	# Also check scene tree for blocks at this position
	var block_name = "Block_" + str(pos_key.x) + "_" + str(pos_key.y) + "_" + str(pos_key.z)
	var existing_node = blocks_container.get_node_or_null(block_name)
	if existing_node and is_instance_valid(existing_node) and existing_node.is_inside_tree():
		var existing_key = to_grid_key_from_world(existing_node.global_position)
		if existing_key == pos_key:
			# Update dictionary and return false
			blocks_by_position[pos_key] = existing_node as StaticBody3D
			return false
	
	# Get block instance from BlockManager (use fast template method if available)
	if not block_manager:
		return false
	
	var static_body: StaticBody3D = null
	if block_manager.has_method("get_block_fast"):
		static_body = block_manager.get_block_fast(block_type, exact_position)
	else:
		# Fallback to slow path
		var block_instance = block_manager.get_block_instance(block_type)
		if block_instance == null:
			return false
		block_instance.name = "Block_" + str(pos_key.x) + "_" + str(pos_key.y) + "_" + str(pos_key.z)
		block_instance.set_meta("block_type", block_type)
		static_body = block_manager.create_block_with_physics(block_instance, exact_position)
	
	if static_body == null:
		return false
	
	# Set name and metadata
	static_body.name = "Block_" + str(pos_key.x) + "_" + str(pos_key.y) + "_" + str(pos_key.z)
	static_body.set_meta("block_type", block_type)
	
	# ATOMIC: Track block position BEFORE adding to scene (prevents race conditions)
	blocks_by_position[pos_key] = static_body
	
	# Add to scene
	blocks_container.add_child(static_body)
	static_body.owner = blocks_container
	
	# CRITICAL: Place exactly on grid using integer math - verify after adding
	static_body.position = exact_position
	
	# Verify position is correct after adding to scene tree
	if static_body.is_inside_tree():
		var actual_global = static_body.global_position
		var expected_global = exact_position  # Since blocks_container is at origin
		
		# If position doesn't match, correct it
		if not actual_global.is_equal_approx(expected_global):
			static_body.position = exact_position
			# Force update
			static_body.set_notify_transform(true)
	
	block_manager.ensure_block_collision(static_body)
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	
	return true

func get_block_at_position(position: Vector3) -> StaticBody3D:
	var pos_key := to_grid_key_from_world(position)
	if blocks_by_position.has(pos_key):
		return blocks_by_position[pos_key] as StaticBody3D
	return null

func place_initial_vegetation():
	# Place vegetation for all initial chunks asynchronously (after terrain is ready)
	await get_tree().process_frame  # Wait one frame to ensure terrain is fully ready
	await get_tree().process_frame  # Wait another frame to ensure chunks are marked as generated
	
	# Wait a bit more for chunks to be fully generated and marked
	await get_tree().create_timer(0.1).timeout
	
	print("Starting vegetation placement for ", generated_chunks.size(), " chunks...")
	var veg_chunks_processed = 0
	
	# Make a copy of generated_chunks keys since it may be modified during iteration
	var chunks_to_process = []
	for chunk_key in generated_chunks:
		chunks_to_process.append(chunk_key)
	
	for chunk_key in chunks_to_process:
		var chunk_x = chunk_key.x
		var chunk_z = chunk_key.y
		
		# Recalculate surface heights for this chunk
		var world_start_x = chunk_x * CHUNK_SIZE
		var world_start_z = chunk_z * CHUNK_SIZE
		var surface_heights = {}
		for x in range(world_start_x, world_start_x + CHUNK_SIZE):
			for z in range(world_start_z, world_start_z + CHUNK_SIZE):
				var noise_value = terrain_noise.get_noise_2d(x, z)
				var height = int((noise_value + 1.0) * 0.5 * terrain_height_multiplier) + MIN_HEIGHT
				height = clamp(height, MIN_HEIGHT, MAX_HEIGHT)
				surface_heights[Vector2i(x, z)] = height
		
		await place_vegetation_for_chunk(chunk_x, chunk_z, surface_heights)
		veg_chunks_processed += 1
		if veg_chunks_processed % 5 == 0:
			await get_tree().process_frame  # Yield periodically
	
	print("Vegetation placement complete! Processed ", veg_chunks_processed, " chunks")

func place_vegetation_for_chunk(chunk_x: int, chunk_z: int, surface_heights: Dictionary):
	# Place vegetation for a chunk (called asynchronously after block generation)
	var world_start_x = chunk_x * CHUNK_SIZE
	var world_start_z = chunk_z * CHUNK_SIZE
	
	var veg_placed = 0
	var grass_blocks_found = 0
	for veg_x in range(world_start_x, world_start_x + CHUNK_SIZE):
		for veg_z in range(world_start_z, world_start_z + CHUNK_SIZE):
			var surface_height = surface_heights.get(Vector2i(veg_x, veg_z), 0)
			var pos_key_2d = Vector2i(veg_x, veg_z)
			
			# Check if vegetation already exists at this position
			if vegetation_positions.has(pos_key_2d):
				continue
			
			# Only place vegetation on grass blocks (surface blocks)
			var pos_key_3d = Vector3i(veg_x, surface_height, veg_z)
			var block_at_surface = blocks_by_position.get(pos_key_3d)
			
			# Check if block exists (could be StaticBody3D, true marker, or null)
			if not blocks_by_position.has(pos_key_3d):
				continue
			
			# Check if it's a grass block
			var is_grass = false
			# Check if it's a bool marker (merged mesh) or a StaticBody3D (individual block)
			if typeof(block_at_surface) == TYPE_BOOL and block_at_surface == true:
				# Merged mesh block - check chunk block data
				var chunk_key = Vector2i(chunk_x, chunk_z)
				if chunk_block_data.has(chunk_key):
					var block_data = chunk_block_data[chunk_key]
					if block_data.has(pos_key_3d):
						var block_type = block_data[pos_key_3d]
						if block_type == BlockManagerScript.BlockType.GRASS:
							is_grass = true
							grass_blocks_found += 1
			elif block_at_surface is StaticBody3D and is_instance_valid(block_at_surface):
				# Individual block - check meta
				if block_at_surface.has_meta("block_type"):
					var block_type = block_at_surface.get_meta("block_type")
					if block_type == BlockManagerScript.BlockType.GRASS:
						is_grass = true
						grass_blocks_found += 1
			
			if not is_grass:
				continue
			
			# Use actual random chance for vegetation placement (noise was too restrictive)
			# Combine noise with random to get varied but predictable placement
			var veg_noise = vegetation_noise.get_noise_2d(veg_x, veg_z)
			var noise_factor = (veg_noise + 1.0) * 0.5  # Normalize to 0..1
			var random_roll = randf()  # Actual random number 0..1
			
			# Use noise to create clusters, but random to determine placement within clusters
			# If noise is high (good spot), increase chance of vegetation
			var effective_tree_chance = tree_chance * (0.5 + noise_factor)  # 0.5x to 1.5x base chance
			var effective_bush_chance = bush_chance * (0.5 + noise_factor)
			
			# Get the actual block's top surface position (blocks are 1 unit tall)
			var block_top_position: Vector3
			if typeof(block_at_surface) == TYPE_BOOL and block_at_surface == true:
				# Merged mesh - calculate position from grid
				block_top_position = to_world_from_grid(pos_key_3d) + Vector3(0, BLOCK_SIZE, 0)
			elif block_at_surface is StaticBody3D:
				# Individual block
				block_top_position = block_at_surface.global_position + Vector3(0, BLOCK_SIZE, 0)
			else:
				# Fallback: calculate from grid
				block_top_position = to_world_from_grid(pos_key_3d) + Vector3(0, BLOCK_SIZE, 0)
			
			# Check for tree placement
			if random_roll < effective_tree_chance:
				if use_multimesh_vegetation:
					add_vegetation_to_multimesh(tree_models, block_top_position, "tree")
					vegetation_positions[pos_key_2d] = true
					veg_placed += 1
				else:
					if await place_vegetation(tree_models, block_top_position, "Tree"):
						vegetation_positions[pos_key_2d] = true
						veg_placed += 1
			# Check for bush placement (only if no tree was placed)
			elif random_roll < effective_tree_chance + effective_bush_chance:
				if use_multimesh_vegetation:
					add_vegetation_to_multimesh(bush_models, block_top_position, "bush")
					vegetation_positions[pos_key_2d] = true
					veg_placed += 1
				else:
					if await place_vegetation(bush_models, block_top_position, "Bush"):
						vegetation_positions[pos_key_2d] = true
						veg_placed += 1
			
			# Yield less frequently for faster generation
			if veg_placed % VEGETATION_BATCH_SIZE == 0:
				await get_tree().process_frame
	
	if grass_blocks_found > 0:
		print("Chunk (", chunk_x, ", ", chunk_z, "): Found ", grass_blocks_found, " grass blocks, placed ", veg_placed, " vegetation")
	
	# If MultiMesh vegetation is enabled, build MultiMesh after placing all vegetation for this chunk
	if use_multimesh_vegetation:
		if multimesh_tree_transforms.size() > 0:
			build_multimesh_vegetation("tree")
		if multimesh_bush_transforms.size() > 0:
			build_multimesh_vegetation("bush")

func place_vegetation(models: PackedStringArray, position: Vector3, type: String) -> bool:
	# Note: This function uses await internally, so it's a coroutine
	# Randomly select a model from the array
	if models.is_empty():
		print("Warning: No ", type, " models available")
		return false
	
	var model_name = models[randi() % models.size()]
	var gltf_path = "res://Assets/gltf/" + model_name + ".gltf"
	
	# Check if file exists
	if not ResourceLoader.exists(gltf_path):
		print("Warning: Vegetation model not found: ", gltf_path)
		return false
	
	# Load and instantiate the model
	var gltf_scene = load(gltf_path) as PackedScene
	if gltf_scene == null:
		print("Error: Failed to load vegetation model: ", gltf_path)
		return false
	
	var instance = gltf_scene.instantiate()
	if instance == null:
		print("Error: Failed to instantiate vegetation model: ", model_name)
		return false
	
	# Remove any physics bodies from vegetation (they're decorative only)
	remove_physics_from_node(instance)
	
	# Get vegetation container (ensure it exists)
	var vegetation_container = get_node_or_null("Vegetation")
	if not vegetation_container:
		# Create it if it doesn't exist
		vegetation_container = Node3D.new()
		vegetation_container.name = "Vegetation"
		vegetation_container.position = Vector3.ZERO
		vegetation_container.rotation = Vector3.ZERO
		vegetation_container.scale = Vector3.ONE
		vegetation_container.transform = Transform3D.IDENTITY
		add_child(vegetation_container)
	
	# Reset scale, rotation, and ensure no transform issues first
	instance.scale = Vector3.ONE
	instance.rotation = Vector3.ZERO
	instance.position = Vector3.ZERO
	
	# Add to vegetation container (must be added before we can get accurate AABB)
	vegetation_container.add_child(instance)
	instance.owner = vegetation_container
	
	# Wait one frame to ensure transforms are properly calculated
	await get_tree().process_frame
	
	# After adding to scene tree, calculate bottom of model and position correctly
	var lowest_local_y = 0.0  # Default: assume origin is at bottom
	if instance.is_inside_tree():
		# Recursively find all MeshInstance3D nodes to get their AABBs
		var mesh_instances = []
		collect_mesh_instances(instance, mesh_instances)
		
		# If we found meshes, calculate the actual bottom
		if mesh_instances.size() > 0:
			# Calculate the bottom of the model in LOCAL space (relative to instance root)
			# We need to find the lowest Y point across all mesh instances
			var calculated_lowest = INF
			
			for mesh_instance in mesh_instances:
				if mesh_instance.mesh:
					# Get AABB in mesh's local space
					var mesh_aabb = mesh_instance.mesh.get_aabb()
					
					# Traverse up the tree to get the total local offset from instance root
					var total_offset = Vector3.ZERO
					var current = mesh_instance
					while current != instance and current != null:
						total_offset += current.position
						current = current.get_parent()
					
					# The AABB's position.y is the bottom of the mesh in its local space
					# Add the total offset to get bottom in instance root's local space
					var mesh_bottom_local_y = total_offset.y + mesh_aabb.position.y
					
					if mesh_bottom_local_y < calculated_lowest:
						calculated_lowest = mesh_bottom_local_y
			
			if calculated_lowest != INF:
				lowest_local_y = calculated_lowest
	
	# Position the vegetation so its bottom aligns with the block's top surface
	# If lowest_local_y is 0, the origin is at the bottom (correct)
	# If lowest_local_y is negative, the origin is above the bottom (need to adjust down)
	# If lowest_local_y is positive, the origin is below the bottom (shouldn't happen, but adjust up)
	instance.position = Vector3(position.x, position.y - lowest_local_y, position.z)
	instance.name = type + "_" + str(int(position.x)) + "_" + str(int(position.y * 10) / 10.0) + "_" + str(int(position.z))
	
	# Add random rotation for variety (only Y axis)
	instance.rotation.y = randf() * TAU

	# Verify it was added correctly
	if instance.is_inside_tree():
		return true
	else:
		print("Error: Failed to add ", type, " to scene tree")
		return false

func collect_mesh_instances(node: Node, mesh_instances: Array):
	# Recursively collect all MeshInstance3D nodes
	if node is MeshInstance3D:
		mesh_instances.append(node)
	for child in node.get_children():
		collect_mesh_instances(child, mesh_instances)

# Performance settings handlers (called from SettingsManager)
func set_render_distance(distance: int):
	GENERATION_DISTANCE = clamp(distance, 1, 8)
	print("Render distance set to: ", GENERATION_DISTANCE, " chunks")

func set_merge_block_meshes(enabled: bool):
	merge_block_meshes = enabled
	print("Mesh merging: ", "enabled" if enabled else "disabled")
	if enabled:
		# Regenerate all chunks with merged meshes
		regenerate_all_chunks_with_merged_meshes()
	else:
		# Remove merged meshes and regenerate with individual blocks
		remove_all_merged_meshes()
		regenerate_all_chunks_with_individual_blocks()

func set_use_multimesh_vegetation(enabled: bool):
	use_multimesh_vegetation = enabled
	print("MultiMesh vegetation: ", "enabled" if enabled else "disabled")
	if enabled:
		# Convert existing vegetation to MultiMesh
		convert_vegetation_to_multimesh()
	else:
		# Convert MultiMesh back to individual instances
		convert_multimesh_to_individual_vegetation()

func set_chunk_physics_only(enabled: bool):
	chunk_physics_only = enabled
	print("Chunk physics: ", "enabled" if enabled else "disabled")
	# If mesh merging is enabled, chunk physics is automatically used
	if merge_block_meshes:
		print("Note: Chunk physics is automatically enabled with mesh merging")
	else:
		# Regenerate chunks to apply/remove chunk physics
		if enabled:
			convert_chunks_to_chunk_physics()
		else:
			convert_chunks_to_block_physics()

func set_face_culling(enabled: bool):
	face_culling_enabled = enabled
	print("Face culling: ", "enabled" if enabled else "disabled")
	# Face culling is applied during mesh generation, so regenerate if mesh merging is enabled
	if merge_block_meshes:
		regenerate_all_chunks_with_merged_meshes()

# ==================== MESH MERGING AND FACE CULLING ====================

func is_face_visible(block_pos: Vector3i, face: int) -> bool:
	# Check if a face is visible (not covered by adjacent block)
	# Face directions: 0=Top, 1=Bottom, 2=North, 3=South, 4=East, 5=West
	if not face_culling_enabled:
		return true  # If face culling disabled, render all faces
	
	var neighbor_pos: Vector3i
	match face:
		0:  # Top (+Y)
			neighbor_pos = block_pos + Vector3i(0, 1, 0)
		1:  # Bottom (-Y)
			neighbor_pos = block_pos + Vector3i(0, -1, 0)
		2:  # North (+Z)
			neighbor_pos = block_pos + Vector3i(0, 0, 1)
		3:  # South (-Z)
			neighbor_pos = block_pos + Vector3i(0, 0, -1)
		4:  # East (+X)
			neighbor_pos = block_pos + Vector3i(1, 0, 0)
		5:  # West (-X)
			neighbor_pos = block_pos + Vector3i(-1, 0, 0)
	
	# Face is visible if there's no block at the neighbor position
	# blocks_by_position can contain true (merged mesh marker), StaticBody3D (individual block), or null
	if blocks_by_position.has(neighbor_pos):
		var neighbor = blocks_by_position[neighbor_pos]
		# If it's a valid StaticBody3D node, face is hidden
		if neighbor is StaticBody3D:
			return false
		# If it's true (bool marker for merged mesh), also hide the face
		if typeof(neighbor) == TYPE_BOOL and neighbor == true:
			return false
	
	return true

func get_block_face_vertices(block_pos: Vector3, face: int) -> PackedVector3Array:
	# Get vertices for a single face of a block at world position
	# Returns 4 vertices in counter-clockwise order (for proper face culling)
	var v0: Vector3
	var v1: Vector3
	var v2: Vector3
	var v3: Vector3
	var half = BLOCK_SIZE * 0.5
	
	match face:
		0:  # Top (+Y)
			v0 = block_pos + Vector3(-half, half, -half)
			v1 = block_pos + Vector3(half, half, -half)
			v2 = block_pos + Vector3(half, half, half)
			v3 = block_pos + Vector3(-half, half, half)
		1:  # Bottom (-Y)
			v0 = block_pos + Vector3(-half, -half, half)
			v1 = block_pos + Vector3(half, -half, half)
			v2 = block_pos + Vector3(half, -half, -half)
			v3 = block_pos + Vector3(-half, -half, -half)
		2:  # North (+Z)
			v0 = block_pos + Vector3(-half, -half, half)
			v1 = block_pos + Vector3(-half, half, half)
			v2 = block_pos + Vector3(half, half, half)
			v3 = block_pos + Vector3(half, -half, half)
		3:  # South (-Z)
			v0 = block_pos + Vector3(half, -half, -half)
			v1 = block_pos + Vector3(half, half, -half)
			v2 = block_pos + Vector3(-half, half, -half)
			v3 = block_pos + Vector3(-half, -half, -half)
		4:  # East (+X)
			v0 = block_pos + Vector3(half, -half, -half)
			v1 = block_pos + Vector3(half, -half, half)
			v2 = block_pos + Vector3(half, half, half)
			v3 = block_pos + Vector3(half, half, -half)
		5:  # West (-X)
			v0 = block_pos + Vector3(-half, -half, half)
			v1 = block_pos + Vector3(-half, -half, -half)
			v2 = block_pos + Vector3(-half, half, -half)
			v3 = block_pos + Vector3(-half, half, half)
	
	return PackedVector3Array([v0, v1, v2, v3])

func get_block_face_uv() -> PackedVector2Array:
	# Standard UV mapping for a block face (0-1 range)
	return PackedVector2Array([
		Vector2(0, 1),
		Vector2(1, 1),
		Vector2(1, 0),
		Vector2(0, 0)
	])

func build_chunk_mesh(chunk_x: int, chunk_z: int) -> ArrayMesh:
	# Build a merged mesh for all blocks in a chunk with face culling
	var chunk_key = Vector2i(chunk_x, chunk_z)
	if not chunk_block_data.has(chunk_key):
		return null
	
	var block_data = chunk_block_data[chunk_key]
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	
	var face_normals = [
		Vector3(0, 1, 0),   # Top
		Vector3(0, -1, 0),  # Bottom
		Vector3(0, 0, 1),   # North
		Vector3(0, 0, -1),  # South
		Vector3(1, 0, 0),   # East
		Vector3(-1, 0, 0)   # West
	]
	
	# Build mesh from block data
	for block_pos_key in block_data.keys():
		var block_pos = to_world_from_grid(block_pos_key)
		
		# Check each face (0-5)
		for face in range(6):
			if is_face_visible(block_pos_key, face):
				var face_vertices = get_block_face_vertices(block_pos, face)
				var face_uv = get_block_face_uv()
				var normal = face_normals[face]
				
				# Add vertices (quad = 4 vertices, 2 triangles)
				var base_index = vertices.size()
				
				# Vertices
				vertices.append_array(face_vertices)
				
				# Normals
				for i in range(4):
					normals.append(normal)
				
				# UVs
				uvs.append_array(face_uv)
				
				# Indices (two triangles: 0-1-2 and 0-2-3)
				indices.append(base_index)
				indices.append(base_index + 1)
				indices.append(base_index + 2)
				indices.append(base_index)
				indices.append(base_index + 2)
				indices.append(base_index + 3)
	
	if vertices.is_empty():
		return null
	
	# Create ArrayMesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return mesh

func create_chunk_mesh_node(chunk_x: int, chunk_z: int) -> MeshInstance3D:
	# Create a MeshInstance3D for a chunk's merged mesh
	var chunk_key = Vector2i(chunk_x, chunk_z)
	var mesh = build_chunk_mesh(chunk_x, chunk_z)
	if mesh == null:
		return null
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "ChunkMesh_%d_%d" % [chunk_x, chunk_z]
	mesh_instance.mesh = mesh
	
	# Apply material (use stone texture for now - can be improved with texture atlas)
	if block_manager and block_manager.has_method("get_texture_for_block_type"):
		var block_data = chunk_block_data.get(chunk_key, {})
		if not block_data.is_empty():
			var first_block_type = block_data.values()[0]
			var texture = block_manager.get_texture_for_block_type(first_block_type)
			if texture:
				var material = StandardMaterial3D.new()
				material.albedo_texture = texture
				material.depth_bias_enabled = true
				material.depth_bias = 0.0001
				material.depth_bias_slope_scale = 1.0
				material.cull_mode = BaseMaterial3D.CULL_BACK
				mesh_instance.material_override = material
	else:
		# Fallback: create basic material
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.8, 0.8, 0.8)
		mesh_instance.material_override = material
	
	# Position at chunk origin
	var world_start_x = chunk_x * CHUNK_SIZE * BLOCK_SIZE
	var world_start_z = chunk_z * CHUNK_SIZE * BLOCK_SIZE
	mesh_instance.position = Vector3(world_start_x, 0, world_start_z)
	
	return mesh_instance

func create_chunk_physics_body(chunk_x: int, chunk_z: int) -> StaticBody3D:
	# Create a single StaticBody3D for the entire chunk
	var chunk_key = Vector2i(chunk_x, chunk_z)
	if not chunk_block_data.has(chunk_key):
		return null
	
	var block_data = chunk_block_data[chunk_key]
	if block_data.is_empty():
		return null
	
	# Create StaticBody3D
	var static_body = StaticBody3D.new()
	static_body.name = "ChunkPhysics_%d_%d" % [chunk_x, chunk_z]
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	
	# Create collision shapes for each block in the chunk
	# For simplicity, use individual BoxShape3D for each block (can be optimized later with ConcavePolygonShape3D)
	for block_pos_key in block_data.keys():
		var block_pos = to_world_from_grid(block_pos_key)
		var collision_shape = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		collision_shape.shape = box_shape
		collision_shape.position = block_pos + Vector3(0, BLOCK_SIZE * 0.5, 0)
		static_body.add_child(collision_shape)
		collision_shape.owner = static_body
	
	# Position at chunk origin
	var world_start_x = chunk_x * CHUNK_SIZE * BLOCK_SIZE
	var world_start_z = chunk_z * CHUNK_SIZE * BLOCK_SIZE
	static_body.position = Vector3(world_start_x, 0, world_start_z)
	
	return static_body

func regenerate_all_chunks_with_merged_meshes():
	# Convert all existing chunks to use merged meshes
	# This is called when mesh merging is enabled
	for chunk_key in generated_chunks.keys():
		var chunk_x = chunk_key.x
		var chunk_z = chunk_key.y
		regenerate_chunk_with_merged_mesh(chunk_x, chunk_z)

func regenerate_chunk_with_merged_mesh(chunk_x: int, chunk_z: int):
	# Regenerate a single chunk using merged mesh
	var chunk_key = Vector2i(chunk_x, chunk_z)
	
	# Collect block data from existing blocks
	var block_data: Dictionary = {}
	var world_start_x = chunk_x * CHUNK_SIZE
	var world_start_z = chunk_z * CHUNK_SIZE
	
	for local_x in range(CHUNK_SIZE):
		for local_z in range(CHUNK_SIZE):
			for y in range(MIN_HEIGHT, MAX_HEIGHT + 1):
				var world_x = world_start_x + local_x
				var world_z = world_start_z + local_z
				var pos_key = Vector3i(world_x, y, world_z)
				
				if blocks_by_position.has(pos_key):
					var block_node = blocks_by_position[pos_key]
					if block_node and is_instance_valid(block_node):
						var block_type = block_node.get_meta("block_type", BlockManagerScript.BlockType.STONE)
						block_data[pos_key] = block_type
	
	# Store block data
	chunk_block_data[chunk_key] = block_data
	
	# Remove existing individual blocks for this chunk
	remove_chunk_blocks(chunk_x, chunk_z)
	
	# Create merged mesh
	var mesh_instance = create_chunk_mesh_node(chunk_x, chunk_z)
	if mesh_instance:
		blocks_container.add_child(mesh_instance)
		mesh_instance.owner = blocks_container
		chunk_meshes[chunk_key] = mesh_instance
		
		# Create chunk physics body
		var physics_body = create_chunk_physics_body(chunk_x, chunk_z)
		if physics_body:
			blocks_container.add_child(physics_body)
			physics_body.owner = blocks_container
			chunk_physics_bodies[chunk_key] = physics_body

func remove_chunk_blocks(chunk_x: int, chunk_z: int):
	# Remove all individual blocks from a chunk
	var world_start_x = chunk_x * CHUNK_SIZE
	var world_start_z = chunk_z * CHUNK_SIZE
	
	for local_x in range(CHUNK_SIZE):
		for local_z in range(CHUNK_SIZE):
			for y in range(MIN_HEIGHT, MAX_HEIGHT + 1):
				var world_x = world_start_x + local_x
				var world_z = world_start_z + local_z
				var pos_key = Vector3i(world_x, y, world_z)
				
				if blocks_by_position.has(pos_key):
					var block_node = blocks_by_position[pos_key]
					if block_node and is_instance_valid(block_node):
						if block_node.get_parent():
							block_node.get_parent().remove_child(block_node)
						block_node.queue_free()
						blocks_by_position.erase(pos_key)

func remove_all_merged_meshes():
	# Remove all merged mesh nodes
	for chunk_key in chunk_meshes.keys():
		var mesh_instance = chunk_meshes[chunk_key]
		if mesh_instance and is_instance_valid(mesh_instance):
			if mesh_instance.get_parent():
				mesh_instance.get_parent().remove_child(mesh_instance)
			mesh_instance.queue_free()
	chunk_meshes.clear()
	
	for chunk_key in chunk_physics_bodies.keys():
		var physics_body = chunk_physics_bodies[chunk_key]
		if physics_body and is_instance_valid(physics_body):
			if physics_body.get_parent():
				physics_body.get_parent().remove_child(physics_body)
			physics_body.queue_free()
	chunk_physics_bodies.clear()
	
	chunk_block_data.clear()

func regenerate_all_chunks_with_individual_blocks():
	# Regenerate all chunks using individual blocks (disable mesh merging)
	# This would require regenerating the terrain, which is expensive
	# For now, just remove merged meshes and let normal generation handle it
	remove_all_merged_meshes()
	print("Note: Chunks will regenerate with individual blocks as you move around")

func convert_chunks_to_chunk_physics():
	# Convert existing chunks to use chunk-based physics
	# This is similar to mesh merging but only affects physics
	print("Note: Chunk physics conversion not fully implemented yet - requires mesh merging")

func convert_chunks_to_block_physics():
	# Convert chunks back to per-block physics
	print("Note: Block physics conversion not fully implemented yet - requires mesh merging")

# ==================== MULTIMESH VEGETATION ====================

func convert_vegetation_to_multimesh():
	# Convert all existing vegetation instances to MultiMesh
	var vegetation_container = get_node_or_null("Vegetation")
	if not vegetation_container:
		return
	
	# Collect all tree and bush instances
	var tree_instances = []
	var bush_instances = []
	
	for child in vegetation_container.get_children():
		if child.name.begins_with("Tree_"):
			tree_instances.append(child)
		elif child.name.begins_with("Bush_"):
			bush_instances.append(child)
	
	# Create MultiMesh for trees
	if tree_instances.size() > 0:
		create_multimesh_vegetation("tree", tree_instances)
	
	# Create MultiMesh for bushes
	if bush_instances.size() > 0:
		create_multimesh_vegetation("bush", bush_instances)
	
	# Remove individual instances
	for instance in tree_instances:
		if instance.get_parent():
			instance.get_parent().remove_child(instance)
		instance.queue_free()
	
	for instance in bush_instances:
		if instance.get_parent():
			instance.get_parent().remove_child(instance)
		instance.queue_free()

func create_multimesh_vegetation(type: String, instances: Array):
	# Create a MultiMeshInstance3D from vegetation instances
	var vegetation_container = get_node_or_null("Vegetation")
	if not vegetation_container or instances.is_empty():
		return
	
	# Get the first instance's mesh (assume all instances of same type use same mesh)
	var first_instance = instances[0]
	var mesh_instances = []
	collect_mesh_instances(first_instance, mesh_instances)
	
	if mesh_instances.is_empty():
		return
	
	var source_mesh_instance = mesh_instances[0]
	var source_mesh = source_mesh_instance.mesh
	if source_mesh == null:
		return
	
	# Create MultiMesh
	var multimesh = MultiMesh.new()
	multimesh.mesh = source_mesh
	multimesh.instance_count = instances.size()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	
	# Collect transforms and materials
	var transforms: Array[Transform3D] = []
	var materials = []
	
	for instance in instances:
		var transform = instance.transform
		transform.origin = instance.global_position  # Use global position
		transforms.append(transform)
		
		# Collect material from mesh instance
		if source_mesh_instance.material_override:
			materials.append(source_mesh_instance.material_override)
		elif source_mesh_instance.get_surface_override_material(0):
			materials.append(source_mesh_instance.get_surface_override_material(0))
	
	# Set transforms
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	
	# Create MultiMeshInstance3D
	var multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.name = "MultiMesh_" + type.capitalize()
	multimesh_instance.multimesh = multimesh
	
	# Apply material if available
	if not materials.is_empty() and materials[0] != null:
		multimesh_instance.material_override = materials[0]
	
	vegetation_container.add_child(multimesh_instance)
	multimesh_instance.owner = vegetation_container
	
	# Store reference
	if type == "tree":
		multimesh_trees = multimesh_instance
	else:
		multimesh_bushes = multimesh_instance

func convert_multimesh_to_individual_vegetation():
	# Convert MultiMesh back to individual vegetation instances
	# This is expensive and not commonly needed, so just remove MultiMesh
	if multimesh_trees and is_instance_valid(multimesh_trees):
		if multimesh_trees.get_parent():
			multimesh_trees.get_parent().remove_child(multimesh_trees)
		multimesh_trees.queue_free()
		multimesh_trees = null
	
	if multimesh_bushes and is_instance_valid(multimesh_bushes):
		if multimesh_bushes.get_parent():
			multimesh_bushes.get_parent().remove_child(multimesh_bushes)
		multimesh_bushes.queue_free()
		multimesh_bushes = null
	
	multimesh_tree_transforms.clear()
	multimesh_bush_transforms.clear()
	multimesh_tree_models.clear()
	multimesh_bush_models.clear()
	
	print("Note: MultiMesh vegetation removed - new vegetation will be individual instances")

func add_vegetation_to_multimesh(models: PackedStringArray, position: Vector3, type: String):
	# Add vegetation instance to MultiMesh (deferred - builds MultiMesh later)
	if type == "tree":
		multimesh_tree_transforms.append(Transform3D(Basis(), position))
		multimesh_tree_models.append(models[randi() % models.size()])
	else:
		multimesh_bush_transforms.append(Transform3D(Basis(), position))
		multimesh_bush_models.append(models[randi() % models.size()])
	
	# Build/update MultiMesh periodically (every 10 additions or immediately for first)
	if type == "tree" and multimesh_tree_transforms.size() % 10 == 1:
		build_multimesh_vegetation("tree")
	elif type == "bush" and multimesh_bush_transforms.size() % 10 == 1:
		build_multimesh_vegetation("bush")

func build_multimesh_vegetation(type: String):
	# Build or update MultiMesh for vegetation type
	var vegetation_container = get_node_or_null("Vegetation")
	if not vegetation_container:
		return
	
	var transforms: Array[Transform3D]
	var model_names: Array
	var multimesh_ref: MultiMeshInstance3D
	
	if type == "tree":
		if multimesh_tree_transforms.is_empty():
			return
		transforms = multimesh_tree_transforms
		model_names = multimesh_tree_models
		multimesh_ref = multimesh_trees
	else:
		if multimesh_bush_transforms.is_empty():
			return
		transforms = multimesh_bush_transforms
		model_names = multimesh_bush_models
		multimesh_ref = multimesh_bushes
	
	if transforms.is_empty():
		return
	
	# Get first model to use as mesh source
	var first_model_name = model_names[0]
	var gltf_path = "res://Assets/gltf/" + first_model_name + ".gltf"
	if not ResourceLoader.exists(gltf_path):
		return
	
	var gltf_scene = load(gltf_path) as PackedScene
	if gltf_scene == null:
		return
	
	var temp_instance = gltf_scene.instantiate()
	if temp_instance == null:
		return
	
	# Get mesh from instance
	var mesh_instances = []
	collect_mesh_instances(temp_instance, mesh_instances)
	temp_instance.queue_free()
	
	if mesh_instances.is_empty():
		return
	
	var source_mesh = mesh_instances[0].mesh
	if source_mesh == null:
		return
	
	# Create or update MultiMesh
	var multimesh: MultiMesh
	if multimesh_ref and is_instance_valid(multimesh_ref) and multimesh_ref.multimesh:
		multimesh = multimesh_ref.multimesh
		multimesh.instance_count = transforms.size()
	else:
		multimesh = MultiMesh.new()
		multimesh.mesh = source_mesh
		multimesh.instance_count = transforms.size()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		
		# Create MultiMeshInstance3D
		var multimesh_instance = MultiMeshInstance3D.new()
		multimesh_instance.name = "MultiMesh_" + type.capitalize()
		multimesh_instance.multimesh = multimesh
		
		# Apply material if available
		if mesh_instances[0].material_override:
			multimesh_instance.material_override = mesh_instances[0].material_override
		
		vegetation_container.add_child(multimesh_instance)
		multimesh_instance.owner = vegetation_container
		
		if type == "tree":
			multimesh_trees = multimesh_instance
		else:
			multimesh_bushes = multimesh_instance
	
	# Set transforms (with random Y rotation)
	for i in range(transforms.size()):
		var t = transforms[i]
		var rotated_basis = t.basis.rotated(Vector3.UP, randf() * TAU)
		var final_transform = Transform3D(rotated_basis, t.origin)
		multimesh.set_instance_transform(i, final_transform)

func remove_physics_from_node(node: Node):
	# Remove any physics bodies recursively
	var to_remove = []
	for child in node.get_children():
		if child is RigidBody3D or child is CharacterBody3D or child is Area3D or child is StaticBody3D:
			to_remove.append(child)
		elif child is CollisionShape3D:
			to_remove.append(child)
		else:
			# Recursively check children
			remove_physics_from_node(child)
	
	for child in to_remove:
		node.remove_child(child)
		child.queue_free()

func cleanup_duplicate_blocks_optimized():
	# Optimized cleanup that only checks recently generated chunks near player
	cleanup_call_count += 1
	if not blocks_container or not player or not is_instance_valid(player):
		return

	# Only check blocks in chunks near the player (optimization)
	var player_pos = player.global_position
	var player_chunk = get_chunk_coords(player_pos)
	var check_distance = GENERATION_DISTANCE + 1  # Check slightly beyond generation distance
	
	# Calculate world bounds for the area to check
	var min_chunk_x = player_chunk.x - check_distance
	var max_chunk_x = player_chunk.x + check_distance
	var min_chunk_z = player_chunk.y - check_distance
	var max_chunk_z = player_chunk.y + check_distance
	
	var min_x = min_chunk_x * CHUNK_SIZE * BLOCK_SIZE
	var max_x = (max_chunk_x + 1) * CHUNK_SIZE * BLOCK_SIZE
	var min_z = min_chunk_z * CHUNK_SIZE * BLOCK_SIZE
	var max_z = (max_chunk_z + 1) * CHUNK_SIZE * BLOCK_SIZE

	# Map of grid key -> array of StaticBody3D found in the scene tree (only in checked area)
	var found: Dictionary = {}
	var blocks_checked = 0
	const MAX_BLOCKS_TO_CHECK = 5000  # Limit how many blocks we check per cleanup

	# Pass 1: scan scene children and group by grid key (only in nearby chunks)
	for child in blocks_container.get_children():
		if blocks_checked >= MAX_BLOCKS_TO_CHECK:
			break  # Stop if we've checked enough blocks
			
		if child is StaticBody3D and is_instance_valid(child):
			var pos = child.global_position
			# Only check blocks in the nearby area
			if pos.x >= min_x and pos.x < max_x and pos.z >= min_z and pos.z < max_z:
				var key := to_grid_key_from_world(pos)
				if not found.has(key):
					found[key] = []
				found[key].append(child)
				blocks_checked += 1

	var total_removed := 0

	# Pass 2: for each grid key, keep ONLY ONE block (the dictionary-tracked one if valid)
	for key in found.keys():
		var nodes: Array = found[key]
		if nodes.size() <= 1:
			# Ensure dictionary points to the single node if valid
			if nodes.size() == 1 and is_instance_valid(nodes[0]):
				blocks_by_position[key] = nodes[0] as StaticBody3D
			continue

		# Prefer the node tracked in blocks_by_position, if valid and in the found list
		var keep_node: StaticBody3D = null
		if blocks_by_position.has(key):
			var tracked = blocks_by_position[key]
			if tracked and is_instance_valid(tracked) and tracked.is_inside_tree():
				# Verify tracked node is actually in the found list
				if tracked in nodes:
					keep_node = tracked
		
		# If no valid tracked node, keep the first valid node
		if not keep_node:
			for n in nodes:
				if is_instance_valid(n) and n.is_inside_tree():
					keep_node = n as StaticBody3D
					break

		# Remove ALL other blocks at this position (ensures independence)
		for n in nodes:
			if n != keep_node and is_instance_valid(n):
				# Remove from dictionary if it was tracked
				if blocks_by_position.has(key) and blocks_by_position[key] == n:
					blocks_by_position.erase(key)
				
				# Remove from scene
				if n.get_parent():
					n.get_parent().remove_child(n)
				n.queue_free()
				total_removed += 1

		# Ensure the kept node is tracked in the dictionary and positioned correctly
		if keep_node and keep_node.is_inside_tree():
			blocks_by_position[key] = keep_node
			
			# Verify position is exactly on grid
			var expected_pos = to_world_from_grid(key)
			if not keep_node.position.is_equal_approx(expected_pos):
				keep_node.position = expected_pos
				keep_node.set_notify_transform(true)

	# Pass 3: prune dictionary entries that are invalid or not inside the tree (only for nearby chunks)
	var to_erase: Array[Vector3i] = []
	for key in blocks_by_position.keys():
		# Only check dictionary entries in the nearby area
		var world_pos = to_world_from_grid(key)
		if world_pos.x >= min_x and world_pos.x < max_x and world_pos.z >= min_z and world_pos.z < max_z:
			var node = blocks_by_position[key]
			if node == null or not is_instance_valid(node) or not node.is_inside_tree():
				to_erase.append(key)
			else:
				# Verify the node is actually at the expected position
				var actual_key = to_grid_key_from_world(node.global_position)
				if actual_key != key:
					to_erase.append(key)
	
	for key in to_erase:
		blocks_by_position.erase(key)

	if total_removed > 0:
		print("Removed ", total_removed, " duplicate blocks (checked ", blocks_checked, " blocks)")

# Keep old function name for backwards compatibility
func cleanup_duplicate_blocks():
	cleanup_duplicate_blocks_optimized()
