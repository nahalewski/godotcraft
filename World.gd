extends Node3D

# World - Generates Minecraft-like terrain with height variation and caves
# Supports infinite terrain generation with chunk-based loading

const CHUNK_SIZE = 16  # Size of each chunk (16x16 blocks)
const MAP_SIZE = 64  # Initial map size (will be expanded dynamically)
const BLOCK_SIZE = 1.0  # Size of each block in world units
const MAX_HEIGHT = 32  # Maximum terrain height
const MIN_HEIGHT = 0   # Minimum terrain height (sea level)
const BEDROCK_LAYER = 3  # Number of bedrock layers at bottom
const GENERATION_DISTANCE = 1  # Generate chunks this many chunks away from player (reduced for performance)
const INITIAL_GENERATION_DISTANCE = 0  # Start with just 1 chunk for fastest loading

# Performance settings
const BLOCKS_PER_FRAME = 200  # Process more blocks per frame before yielding
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

# Track which chunks have been generated (chunk coordinates)
var generated_chunks: Dictionary = {}  # Key: Vector2i(chunk_x, chunk_z), Value: true

# Track chunks currently being generated to prevent race conditions
var generating_chunks: Dictionary = {}  # Key: Vector2i(chunk_x, chunk_z), Value: true

# Cleanup tracking to prevent excessive cleanup calls
var cleanup_call_count: int = 0
var last_cleanup_time: float = 0.0
const CLEANUP_COOLDOWN: float = 5.0  # Minimum seconds between cleanup calls

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

func _ready():
	# Enable VSync on desktop to prevent screen tearing (Android handled separately)
	if OS.get_name() != "Android":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	
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

func generate_chunk(chunk_x: int, chunk_z: int):
	# Check if chunk already generated or currently being generated
	var chunk_key = Vector2i(chunk_x, chunk_z)
	if generated_chunks.has(chunk_key):
		return
	
	# Check if chunk is currently being generated by another coroutine
	if generating_chunks.has(chunk_key):
		return
	
	# Mark chunk as being generated BEFORE any block creation (prevents race conditions)
	generating_chunks[chunk_key] = true
	
	# Error handling: ensure we clear the generating flag even if generation fails
	var generation_failed = false
	
	# Calculate world coordinates for this chunk
	var world_start_x = chunk_x * CHUNK_SIZE
	var world_start_z = chunk_z * CHUNK_SIZE
	
	# First pass: Calculate surface heights for this chunk
	var surface_heights = {}
	for x in range(world_start_x, world_start_x + CHUNK_SIZE):
		for z in range(world_start_z, world_start_z + CHUNK_SIZE):
			# Get terrain height using noise
			var noise_value = terrain_noise.get_noise_2d(x, z)
			# Normalize from -1..1 to MIN_HEIGHT..MAX_HEIGHT
			var height = int((noise_value + 1.0) * 0.5 * terrain_height_multiplier) + MIN_HEIGHT
			height = clamp(height, MIN_HEIGHT, MAX_HEIGHT)
			surface_heights[Vector2i(x, z)] = height
	
	# Second pass: Generate blocks for this chunk
	var blocks_created = 0
	for x in range(world_start_x, world_start_x + CHUNK_SIZE):
		for z in range(world_start_z, world_start_z + CHUNK_SIZE):
			var surface_height = surface_heights[Vector2i(x, z)]
			
			# Generate blocks from bedrock up to surface
			for y in range(surface_height + 1):
				# Skip air blocks (caves)
				if should_be_cave(x, y, z, surface_height):
					continue
				
				# Determine block type based on height
				var block_type = get_block_type_for_height(y, surface_height)
				
				# Calculate block position - use consistent integer calculations
				# Position key: Vector3i for exact integer coordinates
				var pos_key = Vector3i(int(x), int(y), int(z))
				# Actual position: Vector3 with float values at exact integer coordinates
				var exact_position = Vector3(float(int(x)), float(int(y)), float(int(z)))
				
				# ATOMIC duplicate check: Check scene tree first, then dictionary
				# This prevents race conditions by checking the actual scene state
				var should_skip = false
				
				# First: Check if a block with this name already exists in the scene tree
				if blocks_container:
					var block_name = "Block_" + str(x) + "_" + str(y) + "_" + str(z)
					var existing_node = blocks_container.get_node_or_null(block_name)
					if existing_node and is_instance_valid(existing_node):
						# Verify it's actually at the expected position using global_position
						var existing_pos = Vector3i(
							int(round(existing_node.global_position.x)),
							int(round(existing_node.global_position.y)),
							int(round(existing_node.global_position.z))
						)
						if existing_pos == pos_key and existing_node.is_inside_tree():
							should_skip = true
							# Update dictionary if needed (block exists in scene but not tracked)
							if not blocks_by_position.has(pos_key):
								blocks_by_position[pos_key] = existing_node
				
				# Second: Check dictionary for existing block at this position
				if not should_skip and blocks_by_position.has(pos_key):
					var existing_block = blocks_by_position[pos_key]
					if existing_block and is_instance_valid(existing_block):
						# Verify block is actually in the scene tree at the correct position
						if existing_block.is_inside_tree():
							var existing_pos = Vector3i(
								int(round(existing_block.global_position.x)),
								int(round(existing_block.global_position.y)),
								int(round(existing_block.global_position.z))
							)
							if existing_pos == pos_key:
								should_skip = true
							else:
								# Block is at wrong position - remove from dictionary
								blocks_by_position.erase(pos_key)
						else:
							# Block exists but not in tree, remove from tracking
							blocks_by_position.erase(pos_key)
				
				if should_skip:
					continue
				
				# Final check: Verify position is still free right before creation
				# This is the atomic check-and-set point
				if blocks_by_position.has(pos_key):
					var existing = blocks_by_position[pos_key]
					if existing and is_instance_valid(existing) and existing.is_inside_tree():
						var existing_pos = Vector3i(
							int(round(existing.global_position.x)),
							int(round(existing.global_position.y)),
							int(round(existing.global_position.z))
						)
						if existing_pos == pos_key:
							continue  # Another block was just added, skip
				
				# Get block instance
				var block_instance = BlockManager.get_block_instance(block_type)
				if block_instance == null:
					generation_failed = true
					continue
				
				# Set name and metadata
				block_instance.name = "Block_" + str(x) + "_" + str(y) + "_" + str(z)
				block_instance.set_meta("block_type", block_type)
				
				# Create StaticBody3D wrapper with exact position
				# Position is calculated consistently in create_block_with_physics
				var static_body = BlockManager.create_block_with_physics(block_instance, exact_position)
				
				# ATOMIC: Track block position BEFORE adding to scene (prevents race conditions)
				# This ensures any concurrent generation will see this block
				blocks_by_position[pos_key] = static_body
				
				# Add to scene FIRST
				blocks_container.add_child(static_body)
				static_body.owner = blocks_container
				
				# CRITICAL: After adding to scene tree, explicitly set position to exact integer coordinates
				# This ensures no floating-point drift or parent transform interference
				if static_body.is_inside_tree():
					# Calculate the local position needed to achieve the desired global position
					# Since blocks_container should be at origin, position and global_position should match
					static_body.position = exact_position
					
					# Verify global position is correct (should match exact_position if parent is at origin)
					var actual_global = static_body.global_position
					if abs(actual_global.x - exact_position.x) > 0.001 or abs(actual_global.y - exact_position.y) > 0.001 or abs(actual_global.z - exact_position.z) > 0.001:
						# Parent has transform - calculate correct local position
						var parent_global = blocks_container.global_transform.origin
						var correct_local = exact_position - parent_global
						static_body.position = correct_local
						print("WARNING: Block position adjusted at ", pos_key, " - parent transform detected, local pos: ", correct_local)
					
					BlockManager.ensure_block_collision(static_body)
					static_body.collision_layer = 1
					static_body.collision_mask = 0
				
				blocks_created += 1
				
				# Yield less frequently for faster generation
				if blocks_created % BLOCKS_PER_FRAME == 0:
					await get_tree().process_frame
		
		# Vegetation placement is deferred until after terrain is ready for faster loading
		# This allows the player to start playing while vegetation loads in the background
	
	# Mark chunk as generated only after all blocks are successfully created
	# Clear the generating flag
	generating_chunks.erase(chunk_key)
	if not generation_failed:
		generated_chunks[chunk_key] = true

func get_chunk_coords(world_pos: Vector3) -> Vector2i:
	# Convert world position to chunk coordinates
	var chunk_x = int(floor(world_pos.x / CHUNK_SIZE))
	var chunk_z = int(floor(world_pos.z / CHUNK_SIZE))
	return Vector2i(chunk_x, chunk_z)

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
		
		# Generate chunks one at a time with delays to prevent lag
		for chunk_coords in chunks_to_generate:
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
			
			# Place vegetation asynchronously
			place_vegetation_for_chunk(chunk_coords.x, chunk_coords.y, surface_heights)
			
			# Yield multiple frames between chunks to prevent FPS drops
			await get_tree().process_frame
			await get_tree().process_frame
		
		# Only clean up duplicates occasionally to reduce overhead
		# The duplicate check in generate_chunk should prevent most duplicates anyway
		var current_time = Time.get_ticks_msec() / 1000.0
		if chunks_to_generate.size() >= 10 and (current_time - last_cleanup_time) >= CLEANUP_COOLDOWN:
			cleanup_duplicate_blocks()
			last_cleanup_time = current_time
		
		# Wait longer before checking again to reduce CPU usage
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
				BlockManager.ensure_block_collision(block)
			
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

func get_block_type_for_height(y: int, surface_height: int) -> BlockManager.BlockType:
	# Bedrock layer at bottom
	if y < BEDROCK_LAYER:
		return BlockManager.BlockType.STONE
	
	# Surface layer: grass (topmost block)
	if y == surface_height:
		return BlockManager.BlockType.GRASS
	
	# Just below surface: dirt (topsoil layer, 3 blocks deep)
	if y < surface_height and y >= surface_height - 3:
		return BlockManager.BlockType.DIRT
	
	# Deep underground: stone
	return BlockManager.BlockType.STONE

func remove_block(position: Vector3) -> bool:
	# Use consistent position calculation: round to nearest integer
	var pos_key = Vector3i(
		int(round(position.x)),
		int(round(position.y)),
		int(round(position.z))
	)
	
	# Check if block exists
	if not blocks_by_position.has(pos_key):
		return false
	
	var block = blocks_by_position[pos_key]
	if block and is_instance_valid(block):
		# Remove from tracking FIRST
		blocks_by_position.erase(pos_key)
		
		# Remove from scene
		if block.get_parent():
			block.get_parent().remove_child(block)
		block.queue_free()
		return true
	
	return false

func place_block(block_type: BlockManager.BlockType, position: Vector3) -> bool:
	# Use consistent position calculation: round to nearest integer
	var pos_key = Vector3i(
		int(round(position.x)),
		int(round(position.y)),
		int(round(position.z))
	)
	var exact_position = Vector3(float(int(pos_key.x)), float(int(pos_key.y)), float(int(pos_key.z)))
	
	# Check if position is already occupied (verify in both dictionary and scene tree)
	if blocks_by_position.has(pos_key):
		var existing_block = blocks_by_position[pos_key]
		if existing_block and is_instance_valid(existing_block) and existing_block.is_inside_tree():
			# Verify it's actually at this position
			var existing_pos = Vector3i(
				int(round(existing_block.global_position.x)),
				int(round(existing_block.global_position.y)),
				int(round(existing_block.global_position.z))
			)
			if existing_pos == pos_key:
				return false
	
	# Also check scene tree for blocks at this position
	if blocks_container:
		var block_name = "Block_" + str(pos_key.x) + "_" + str(pos_key.y) + "_" + str(pos_key.z)
		var existing_node = blocks_container.get_node_or_null(block_name)
		if existing_node and is_instance_valid(existing_node):
			var existing_pos = Vector3i(
				int(round(existing_node.global_position.x)),
				int(round(existing_node.global_position.y)),
				int(round(existing_node.global_position.z))
			)
			if existing_pos == pos_key:
				return false
	
	# Get block instance from BlockManager
	var block_instance = BlockManager.get_block_instance(block_type)
	if block_instance == null:
		return false
	
	# Set name
	block_instance.name = "Block_" + str(pos_key.x) + "_" + str(pos_key.y) + "_" + str(pos_key.z)
	
	# Store block type in metadata
	block_instance.set_meta("block_type", block_type)
	
	# Create StaticBody3D wrapper with exact position
	var static_body = BlockManager.create_block_with_physics(block_instance, exact_position)
	
	# ATOMIC: Track block position BEFORE adding to scene (prevents race conditions)
	blocks_by_position[pos_key] = static_body
	
	# Add to scene FIRST
	blocks_container.add_child(static_body)
	static_body.owner = blocks_container
	
	# CRITICAL: After adding to scene tree, explicitly set position to exact integer coordinates
	# This ensures no floating-point drift or parent transform interference
	if static_body.is_inside_tree():
		# Calculate the local position needed to achieve the desired global position
		# Since blocks_container should be at origin, position and global_position should match
		static_body.position = exact_position
		
		# Verify global position is correct (should match exact_position if parent is at origin)
		var actual_global = static_body.global_position
		if abs(actual_global.x - exact_position.x) > 0.001 or abs(actual_global.y - exact_position.y) > 0.001 or abs(actual_global.z - exact_position.z) > 0.001:
			# Parent has transform - calculate correct local position
			var parent_global = blocks_container.global_transform.origin
			var correct_local = exact_position - parent_global
			static_body.position = correct_local
			print("WARNING: Block position adjusted at ", pos_key, " - parent transform detected, local pos: ", correct_local)
		
		BlockManager.ensure_block_collision(static_body)
		# Force physics update
		static_body.set_notify_transform(true)
		# Verify collision was added
		var has_collision = false
		for child in static_body.get_children():
			if child is CollisionShape3D and child.shape != null:
				has_collision = true
				break
		if not has_collision:
			print("WARNING: Block placed without collision at ", exact_position)
			# Try again
			BlockManager.ensure_block_collision(static_body)
	
	return true

func get_block_at_position(position: Vector3) -> StaticBody3D:
	var pos_key = Vector3i(int(position.x), int(position.y), int(position.z))
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
			var block_at_surface = blocks_by_position.get(Vector3i(veg_x, surface_height, veg_z))
			if not block_at_surface:
				continue
			
			# Verify block is valid and in scene
			if not is_instance_valid(block_at_surface) or not block_at_surface.is_inside_tree():
				continue
			
			# Check if it's a grass block
			var is_grass = false
			if block_at_surface.has_meta("block_type"):
				var block_type = block_at_surface.get_meta("block_type")
				if block_type == BlockManager.BlockType.GRASS:
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
			
			# Check for tree placement
			if random_roll < effective_tree_chance:
				var tree_pos = Vector3(float(int(veg_x)), float(int(surface_height)) + 1.0, float(int(veg_z)))
				if place_vegetation(tree_models, tree_pos, "Tree"):
					vegetation_positions[pos_key_2d] = true
					veg_placed += 1
			# Check for bush placement (only if no tree was placed)
			elif random_roll < effective_tree_chance + effective_bush_chance:
				var bush_pos = Vector3(float(int(veg_x)), float(int(surface_height)) + 1.0, float(int(veg_z)))
				if place_vegetation(bush_models, bush_pos, "Bush"):
					vegetation_positions[pos_key_2d] = true
					veg_placed += 1
			
			# Yield less frequently for faster generation
			if veg_placed % VEGETATION_BATCH_SIZE == 0:
				await get_tree().process_frame
	
	if grass_blocks_found > 0:
		print("Chunk (", chunk_x, ", ", chunk_z, "): Found ", grass_blocks_found, " grass blocks, placed ", veg_placed, " vegetation")

func place_vegetation(models: PackedStringArray, position: Vector3, type: String) -> bool:
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
	
	# Position the vegetation - use exact integer coordinates
	var exact_pos = Vector3(float(int(position.x)), float(int(position.y)), float(int(position.z)))
	instance.position = exact_pos
	instance.name = type + "_" + str(int(exact_pos.x)) + "_" + str(int(exact_pos.y)) + "_" + str(int(exact_pos.z))
	
	# Add random rotation for variety
	instance.rotation.y = randf() * TAU  # Random rotation around Y axis (0 to 360 degrees)
	
	# Add to vegetation container
	vegetation_container.add_child(instance)
	instance.owner = vegetation_container
	
	# Verify it was added correctly
	if instance.is_inside_tree():
		return true
	else:
		print("Error: Failed to add ", type, " to scene tree")
		return false

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

func cleanup_duplicate_blocks():
	# Remove any duplicate blocks at the same position
	# Also remove invalid block references
	# Only print if duplicates are actually found to reduce log spam
	cleanup_call_count += 1
	
	var blocks_at_position: Dictionary = {}  # Track all blocks at each position
	var duplicate_count = 0
	
	# First pass: identify duplicates by checking actual scene tree using global_position
	if not blocks_container:
		return
	
	# Scan all blocks in the scene tree and verify their actual positions
	for child in blocks_container.get_children():
		if not child is StaticBody3D:
			continue
		
		var block = child as StaticBody3D
		if not is_instance_valid(block):
			continue
		
		# Get actual block position using global_position (most accurate)
		# Round to nearest integer to match block grid
		var block_pos = Vector3i(
			int(round(block.global_position.x)),
			int(round(block.global_position.y)),
			int(round(block.global_position.z))
		)
		
		# Track blocks at this position
		if not blocks_at_position.has(block_pos):
			blocks_at_position[block_pos] = []
		blocks_at_position[block_pos].append(block)
	
	# Second pass: remove duplicates (keep only the first valid one)
	for pos_key in blocks_at_position:
		var blocks = blocks_at_position[pos_key]
		if blocks.size() > 1:
			# Multiple blocks at same position - verify which one to keep
			# Keep the first one that is properly tracked in dictionary, or first valid one
			var keep_block = null
			var blocks_to_remove = []
			
			for block in blocks:
				if not block or not is_instance_valid(block):
					blocks_to_remove.append(block)
					continue
				
				# Verify block is actually at this position
				var actual_pos = Vector3i(
					int(round(block.global_position.x)),
					int(round(block.global_position.y)),
					int(round(block.global_position.z))
				)
				if actual_pos != pos_key:
					# Block is at wrong position, remove it
					blocks_to_remove.append(block)
					continue
				
				# Prefer keeping the block that's tracked in dictionary
				if keep_block == null:
					if blocks_by_position.has(pos_key) and blocks_by_position[pos_key] == block:
						keep_block = block
					else:
						keep_block = block  # Use first valid block if none tracked
				else:
					# Check if this block is the tracked one (prefer it)
					if blocks_by_position.has(pos_key) and blocks_by_position[pos_key] == block:
						blocks_to_remove.append(keep_block)
						keep_block = block
					else:
						blocks_to_remove.append(block)
			
			# Remove duplicate blocks
			duplicate_count += blocks_to_remove.size()
			if blocks_to_remove.size() > 0:
				print("Found ", blocks.size(), " blocks at position ", pos_key, ", removing ", blocks_to_remove.size(), " duplicates")
			
			for duplicate_block in blocks_to_remove:
				if duplicate_block and is_instance_valid(duplicate_block):
					# Remove from tracking dictionary if it's the tracked one
					if blocks_by_position.has(pos_key) and blocks_by_position[pos_key] == duplicate_block:
						# Only remove if we're keeping a different block
						if keep_block != duplicate_block:
							blocks_by_position[pos_key] = keep_block
							if not keep_block:
								blocks_by_position.erase(pos_key)
					# Remove from scene tree immediately
					if duplicate_block.get_parent():
						duplicate_block.get_parent().remove_child(duplicate_block)
					duplicate_block.queue_free()
			
			# Ensure the kept block is tracked in dictionary
			if keep_block and keep_block.is_inside_tree():
				blocks_by_position[pos_key] = keep_block
	
	# Third pass: clean up dictionary - remove invalid entries and verify positions
	var dict_keys_to_remove = []
	for pos_key in blocks_by_position:
		var block = blocks_by_position[pos_key]
		if not block or not is_instance_valid(block) or not block.is_inside_tree():
			dict_keys_to_remove.append(pos_key)
		else:
			# Verify the block is actually at the expected position
			var actual_pos = Vector3i(
				int(round(block.global_position.x)),
				int(round(block.global_position.y)),
				int(round(block.global_position.z))
			)
			if actual_pos != pos_key:
				# Block is at wrong position - remove from dictionary
				dict_keys_to_remove.append(pos_key)
	
	for pos_key in dict_keys_to_remove:
		blocks_by_position.erase(pos_key)
	
	# Only print if duplicates were actually found
	if duplicate_count > 0:
		print("Removed ", duplicate_count, " duplicate blocks")
