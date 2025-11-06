extends Node3D

# Day/Night Cycle - Controls sun and moon rotation, lighting, and sky colors

@export var day_length_minutes: float = 20.0  # Real-world minutes for a full day/night cycle
@export var start_time: float = 0.5  # Start time (0.0 = midnight, 0.5 = noon, 1.0 = midnight)

var time_of_day: float = 0.5  # 0.0 to 1.0 (0 = midnight, 0.5 = noon)
var sun_light: DirectionalLight3D
var moon_light: DirectionalLight3D
var moon_mesh: MeshInstance3D

# Time calculation
var seconds_per_day: float
var current_time_seconds: float = 0.0

func _ready():
	# Calculate seconds per day based on day length
	seconds_per_day = day_length_minutes * 60.0
	current_time_seconds = start_time * seconds_per_day
	
	# Find or create sun light (it's a sibling node in Main)
	sun_light = get_node_or_null("../DirectionalLight3D")
	if not sun_light:
		sun_light = DirectionalLight3D.new()
		sun_light.name = "SunLight"
		get_parent().add_child(sun_light)
	
	# Create moon light (weaker, bluish)
	moon_light = DirectionalLight3D.new()
	moon_light.name = "MoonLight"
	moon_light.light_color = Color(0.7, 0.8, 1.0)  # Bluish moonlight
	moon_light.light_energy = 0.3
	moon_light.shadow_enabled = false  # Disable shadows for better performance
	add_child(moon_light)
	
	# Create moon mesh (simple sphere)
	create_moon()
	
	# Set initial sun properties
	sun_light.light_color = Color(1.0, 0.95, 0.8)  # Warm sunlight
	sun_light.light_energy = 1.0
	sun_light.shadow_enabled = false  # Disable shadows for better performance

func create_moon():
	# Create a simple sphere for the moon
	var moon_sphere = SphereMesh.new()
	moon_sphere.radius = 2.0
	moon_sphere.height = 4.0
	moon_sphere.radial_segments = 32
	moon_sphere.rings = 16
	
	moon_mesh = MeshInstance3D.new()
	moon_mesh.name = "Moon"
	moon_mesh.mesh = moon_sphere
	
	# Create moon material (glowing white)
	var moon_material = StandardMaterial3D.new()
	moon_material.albedo_color = Color(0.9, 0.9, 0.95)
	moon_material.emission_enabled = true
	moon_material.emission = Color(0.8, 0.8, 0.9)
	moon_material.emission_energy_multiplier = 1.5
	moon_mesh.material_override = moon_material
	
	add_child(moon_mesh)

func _process(delta):
	# Update time
	current_time_seconds += delta
	if current_time_seconds >= seconds_per_day:
		current_time_seconds = 0.0
	
	time_of_day = current_time_seconds / seconds_per_day
	
	# Update sun and moon positions
	update_sun_moon_positions()
	
	# Update lighting based on time
	update_lighting()

func update_sun_moon_positions():
	# Sun rotates 360 degrees over the day
	# At time 0.0 (midnight): sun is below horizon (rotation = 180 degrees)
	# At time 0.5 (noon): sun is at top (rotation = 0 degrees)
	var sun_rotation = (time_of_day - 0.5) * TAU  # -PI to PI
	
	# Convert rotation to direction vector
	var sun_direction = Vector3(
		sin(sun_rotation),
		cos(sun_rotation),
		0.0
	).normalized()
	
	# Set sun light direction (pointing down)
	if sun_light:
		sun_light.rotation_degrees = Vector3(
			rad_to_deg(atan2(sun_direction.y, sun_direction.x)) - 90,
			0,
			0
		)
	
	# Moon is opposite to sun (180 degrees offset)
	var moon_rotation = sun_rotation + PI
	var moon_direction = Vector3(
		sin(moon_rotation),
		cos(moon_rotation),
		0.0
	).normalized()
	
	# Set moon light direction
	if moon_light:
		moon_light.rotation_degrees = Vector3(
			rad_to_deg(atan2(moon_direction.y, moon_direction.x)) - 90,
			0,
			0
		)
	
	# Position moon mesh in the sky (far away, high up)
	if moon_mesh:
		var moon_distance = 100.0
		# Position moon relative to world origin (0, 0, 0)
		moon_mesh.position = moon_direction * moon_distance
		# Make moon face the origin
		moon_mesh.look_at(Vector3.ZERO, Vector3.UP)

func update_lighting():
	# Calculate sun height (0 = below horizon, 1 = directly overhead)
	var sun_height = sin(time_of_day * TAU - PI / 2.0)  # -1 to 1
	sun_height = (sun_height + 1.0) * 0.5  # 0 to 1
	
	# Day time: 0.25 to 0.75 (6am to 6pm)
	var is_day = time_of_day > 0.25 and time_of_day < 0.75
	
	if sun_light:
		if is_day and sun_height > 0.1:
			# Sun is up - bright daylight
			var sun_intensity = clamp((sun_height - 0.1) / 0.4, 0.0, 1.0)
			sun_light.light_energy = lerp(0.3, 1.0, sun_intensity)
			sun_light.visible = true
			
			# Adjust color based on time of day
			if time_of_day < 0.3:  # Morning
				sun_light.light_color = Color(1.0, 0.9, 0.7)  # Warm morning
			elif time_of_day > 0.7:  # Evening
				sun_light.light_color = Color(1.0, 0.8, 0.6)  # Warm evening
			else:  # Midday
				sun_light.light_color = Color(1.0, 0.95, 0.8)  # Bright white
		else:
			# Sun is down - night
			sun_light.light_energy = 0.0
			sun_light.visible = false
	
	if moon_light:
		if not is_day or sun_height < 0.1:
			# Moon is up - moonlight
			var moon_intensity = 1.0 - sun_height
			moon_light.light_energy = lerp(0.1, 0.3, moon_intensity)
			moon_light.visible = true
		else:
			# Moon is down
			moon_light.light_energy = 0.0
			moon_light.visible = false
	
	# Show/hide moon mesh based on visibility
	if moon_mesh:
		moon_mesh.visible = not is_day or sun_height < 0.2

func get_time_string() -> String:
	# Convert time_of_day (0-1) to hours (0-24)
	var hours = int(time_of_day * 24.0)
	var minutes = int((time_of_day * 24.0 - hours) * 60.0)
	return "%02d:%02d" % [hours, minutes]

