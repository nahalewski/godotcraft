extends Node3D

# World - Generates Minecraft-like terrain with height variation and caves

const MAP_SIZE = 64
const BLOCK_SIZE = 1.0  # Size of each block in world units
const MAX_HEIGHT = 32  # Maximum terrain height
const MIN_HEIGHT = 0   # Minimum terrain height (sea level)
const BEDROCK_LAYER = 3  # Number of bedrock layers at bottom

@export var block_spacing: float = 1.0
@export var terrain_noise_scale: float = 0.1  # Controls terrain smoothness
@export var terrain_height_multiplier: float = 15.0  # Height variation amount
@export var cave_threshold: float = 0.3  # Lower = more caves (0.0 to 1.0)
@export var cave_noise_scale: float = 0.15  # Cave size

# Signal emitted when terrain generation is complete and physics is ready
signal terrain_ready

# Noise generators for terrain and caves
var terrain_noise: FastNoiseLite
var cave_noise: FastNoiseLite

func _ready():
	# Initialize noise generators
	terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = randi()
	terrain_noise.frequency = terrain_noise_scale
	terrain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	cave_noise = FastNoiseLite.new()
	cave_noise.seed = randi() + 1000  # Different seed for caves
	cave_noise.frequency = cave_noise_scale
	cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	generate_terrain()

func generate_terrain():
	print("Generating Minecraft-like terrain with caves...")
	
	# Create a parent node for all blocks to keep hierarchy clean
	var blocks_container = Node3D.new()
	blocks_container.name = "Blocks"
	add_child(blocks_container)
	
	# First pass: Calculate surface heights for each column
	var surface_heights = {}
	for x in range(MAP_SIZE):
		for z in range(MAP_SIZE):
			# Get terrain height using noise
			var noise_value = terrain_noise.get_noise_2d(x, z)
			# Normalize from -1..1 to MIN_HEIGHT..MAX_HEIGHT
			var height = int((noise_value + 1.0) * 0.5 * terrain_height_multiplier) + MIN_HEIGHT
			height = clamp(height, MIN_HEIGHT, MAX_HEIGHT)
			surface_heights[Vector2i(x, z)] = height
	
	# Second pass: Generate blocks from bedrock to surface
	var blocks_created = 0
	for x in range(MAP_SIZE):
		for z in range(MAP_SIZE):
			var surface_height = surface_heights[Vector2i(x, z)]
			
			# Generate blocks from bedrock up to surface
			for y in range(BEDROCK_LAYER + surface_height + 1):
				# Skip air blocks (caves)
				if should_be_cave(x, y, z, surface_height):
					continue
				
				# Determine block type based on height
				var block_type = get_block_type_for_height(y, surface_height)
				
				# Get block instance from BlockManager
				var block_instance = BlockManager.get_block_instance(block_type)
				if block_instance == null:
					continue
				
				# Calculate block position
				var block_position = Vector3(
					x * BLOCK_SIZE * block_spacing,
					y * BLOCK_SIZE,
					z * BLOCK_SIZE * block_spacing
				)
				
				# Set name on block_instance
				block_instance.name = "Block_" + str(x) + "_" + str(y) + "_" + str(z)
				
				# Create StaticBody3D wrapper
				var static_body = BlockManager.create_block_with_physics(block_instance, block_position)
				
				# Add to scene
				blocks_container.add_child(static_body)
				static_body.owner = blocks_container
				
				# Ensure collision is set up
				if static_body.is_inside_tree():
					BlockManager.ensure_block_collision(static_body)
				
				blocks_created += 1
				
				# Wait a physics frame every 50 blocks to let physics server catch up
				if blocks_created % 50 == 0:
					await get_tree().physics_frame
				
				# Process a few blocks at a time to avoid blocking
				if blocks_created % 200 == 0:
					await get_tree().process_frame
	
	print("Terrain generation complete! Generated ", blocks_created, " blocks.")
	
	# CRITICAL: Wait for physics server to update after adding all blocks
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Signal that terrain is ready - player can now move
	terrain_ready.emit()
	print("Terrain ready signal emitted - player can now move!")


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
	
	# Surface layer: grass
	if y == surface_height:
		return BlockManager.BlockType.GRASS
	
	# Just below surface: dirt (topsoil)
	if y >= surface_height - 3:
		return BlockManager.BlockType.DIRT
	
	# Deep underground: stone
	return BlockManager.BlockType.STONE
