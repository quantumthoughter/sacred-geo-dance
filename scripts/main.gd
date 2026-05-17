extends Node3D

# ── Audio ──
var audio: AudioStreamPlayer
var dance_data: DanceData
var time: float = 0.0
var beat_energy: float = 0.0
var speed_mult: float = 1.0
var simulated_time: float = 0.0  # for MovieWriter recording
var recording: bool = false
var record_duration: float = 0.0
var record_start: float = 0.0

# ── Input Recording & Replay ──
var input_recording: bool = false
var input_events: Array = []  # {time, keycode, pressed}
var input_record_start: float = 0.0
var replaying: bool = false
var replay_events: Array = []
var replay_index: int = 0
var replay_file: String = "user://replay.json"

# ── Camera ──
var cam: Camera3D
var cam_theta: float = 0.0
var cam_phi: float = 0.35
var cam_radius: float = 8.0
var mouse_cam: bool = true
var mouse_dragging: bool = false
var mouse_last: Vector2 = Vector2.ZERO
var auto_orbit: bool = true

# ── Geometry ──
var geometry_container: Node3D
var mode: int = 0
var platonic_index: int = 0
var torus_p: int = 2
var torus_q: int = 3
var vertex_orbs: Array = []
var edge_nodes: Array = []

# ── Visuals ──
var env_ref: Environment
var starfield: GPUParticles3D
var grid_cage: Node3D
var cage_visible: bool = false
var palette_index: int = 0
var edge_trail_timer: float = 0.0
var orb_shader: ShaderMaterial
var edge_shader: ShaderMaterial

# ── Energy rivers ──
var river_motes: Array = []
var river_data: Array = []  # {fr, to, dir_norm, length}
var rivers_visible: bool = true

# ── Galaxy ──
var galaxy_arms: int = 4
var galaxy_particles: int = 3

const PALETTE_NAMES = ["Cosmic", "Fire", "Aurora", "Neon", "Void", "Prism", "Ocean", "Dawn"]
const PALETTE_HUES = [0.0, 0.07, 0.4, 0.75, 0.58, 0.83, 0.55, 0.12]
const PALETTE_SATS = [0.85, 1.0, 0.9, 1.0, 0.35, 0.95, 0.7, 0.8]
const PALETTE_VALS = [0.9, 1.0, 0.95, 1.0, 0.8, 1.0, 0.85, 0.9]

const MODE_NAMES = [
	"Flower of Life 3D", "Metatron's Cube", "Platonic Solids",
	"Torus Knot", "Fibonacci Spiral", "Cymatics Sphere",
	"Merkaba", "Seed of Life", "Sri Yantra", "Galaxy",
	"Cosmic Rivers"
]
const PLATONIC_NAMES = ["Tetrahedron", "Cube", "Octahedron", "Dodecahedron", "Icosahedron"]


# ═══════════════════════════════════════════
# DanceData (reused from existing format)
# ═══════════════════════════════════════════
class DanceData extends RefCounted:
	var onset: PackedFloat64Array
	var rms: PackedFloat64Array
	var centroid: PackedFloat64Array
	var num_frames: int
	var fps: float

	static func load_file(path: String) -> DanceData:
		var f = FileAccess.open(path, FileAccess.READ)
		if not f: return null
		var j = JSON.new(); j.parse(f.get_as_text())
		var d = j.get_data()
		var dd = DanceData.new()
		dd.onset = PackedFloat64Array(d.get("onset", []))
		dd.rms = PackedFloat64Array(d.get("rms", []))
		dd.centroid = PackedFloat64Array(d.get("centroid", []))
		dd.num_frames = d.get("num_frames", 0)
		dd.fps = d.get("fps", 30)
		return dd

	func feat_at(t: float) -> Dictionary:
		if num_frames <= 0:
			return {"onset": 0, "rms": 0.5, "centroid": 0.5}
		var i = clampi(int(t * fps), 0, num_frames - 1)
		return {
			"onset": onset[i] if i < onset.size() else 0.0,
			"rms": rms[i] if i < rms.size() else 0.5,
			"centroid": centroid[i] if i < centroid.size() else 0.5
		}


# ═══════════════════════════════════════════
# Lifecycle
# ═══════════════════════════════════════════
func _ready():
	_setup_scene()
	_build_current_geometry()
	audio.play()
	# If MovieWriter mode, try loading a replay
	if not audio.playing:
		_load_replay()


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if input_recording and input_events.size() > 0:
			_save_replay()


func _exit_tree():
	if input_recording and input_events.size() > 0:
		_save_replay()


func _setup_scene():
	# Audio player
	audio = AudioStreamPlayer.new()
	add_child(audio)
	var dir = DirAccess.open("res://music")
	dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if fn.get_extension() in ["mp3", "wav"]:
			var s = load("res://music/" + fn)
			if s: audio.stream = s; break
		fn = dir.get_next()

	# Environment — rich cosmic void
	var env = WorldEnvironment.new()
	env_ref = Environment.new()
	env_ref.background_color = Color(0.01, 0.005, 0.03, 1)
	env_ref.ambient_light_color = Color(0.04, 0.02, 0.08, 1)
	env_ref.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_ref.glow_enabled = true
	env_ref.glow_intensity = 3.2
	env_ref.glow_bloom = 0.85
	env_ref.glow_hdr_threshold = 0.4
	env_ref.glow_hdr_scale = 2.5
	env_ref.volumetric_fog_enabled = true
	env_ref.volumetric_fog_density = 0.008
	env_ref.volumetric_fog_albedo = Color(0.06, 0.02, 0.12)
	env_ref.volumetric_fog_emission = Color(0.1, 0.05, 0.2)
	env_ref.volumetric_fog_emission_energy = 0.3
	env.environment = env_ref
	add_child(env)

	# Camera
	cam = Camera3D.new()
	cam.current = true
	cam.fov = 60
	add_child(cam)
	_update_camera_position()

	# Dance data
	dance_data = DanceData.load_file("res://music/the_num_singularity_immersion.dance")

	# HUD label
	var label = Label.new()
	label.name = "Label"
	label.position = Vector2(20, 20)
	label.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0))
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)

	# Geometry root
	geometry_container = Node3D.new()
	geometry_container.name = "GeometryContainer"
	add_child(geometry_container)

	# Starfield
	_create_starfield()

	# Light grid cage (hidden by default)
	_create_grid_cage()

	# Shaders
	orb_shader = ShaderMaterial.new()
	orb_shader.shader = load("res://shaders/energy_orb.gdshader")
	edge_shader = ShaderMaterial.new()
	edge_shader.shader = load("res://shaders/glow_edge.gdshader")


# ═══════════════════════════════════════════
# Camera — spherical orbit
# ═══════════════════════════════════════════
func _update_camera_position():
	cam.position = Vector3(
		cos(cam_theta) * cos(cam_phi) * cam_radius,
		sin(cam_phi) * cam_radius,
		sin(cam_theta) * cos(cam_phi) * cam_radius
	)
	cam.look_at(Vector3.ZERO)


# ═══════════════════════════════════════════
# Geometry lifecycle
# ═══════════════════════════════════════════
func _clear_geometry():
	for child in geometry_container.get_children():
		child.queue_free()
	vertex_orbs.clear()
	edge_nodes.clear()
	river_data.clear()
	_clear_river_motes()


func _build_current_geometry():
	_clear_geometry()
	match mode:
		0: _create_flower_of_life_3d()
		1: _create_metatron_cube()
		2: _create_platonic(platonic_index)
		3: _create_torus_knot(torus_p, torus_q)
		4: _create_fibonacci_spiral()
		5: _create_cymatics_sphere()
		6: _create_merkaba()
		7: _create_seed_of_life()
		8: _create_sri_yantra()
		9: _create_galaxy()
		10: _create_cosmic_rivers()
	_build_river_data()


# ═══════════════════════════════════════════
# Vertex & Edge builders
# ═══════════════════════════════════════════
func _create_vertex(pos: Vector3, radius: float, color: Color):
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh.mesh = sphere
	mesh.position = pos
	var mat = orb_shader.duplicate()
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("fresnel_power", randf_range(1.8, 2.8))
	mat.set_shader_parameter("pulse_speed", randf_range(3.0, 6.0))
	mat.set_shader_parameter("base_brightness", 1.3 + randf() * 0.4)
	mesh.material_override = mat
	geometry_container.add_child(mesh)
	var orb = {
		"node": mesh,
		"base_radius": radius,
		"color": color,
		"phase": randf() * TAU,
		"base_pos": pos
	}
	vertex_orbs.append(orb)
	return orb


func _create_edge(fr: Vector3, to: Vector3, radius: float, color: Color):
	var dir_vec = to - fr
	var length = dir_vec.length()
	if length < 0.001: return
	var mid = (fr + to) / 2.0

	var mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 6
	cyl.rings = 1
	mesh.mesh = cyl
	mesh.position = mid

	# Align cylinder (default Y-up) to direction vector
	var y_ax = Vector3.UP
	var tgt = dir_vec.normalized()
	var dot = y_ax.dot(tgt)
	if dot < -0.9999:
		mesh.rotation = Vector3(1, 0, 0) * PI
	elif dot < 0.9999:
		var axis = y_ax.cross(tgt).normalized()
		var angle = y_ax.angle_to(tgt)
		mesh.rotate(axis, angle)

	var mat = edge_shader.duplicate()
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("brightness", 1.2 + randf() * 0.6)
	mesh.material_override = mat
	geometry_container.add_child(mesh)
	edge_nodes.append(mesh)


func _connect_vertices(points: Array, threshold: float, color: Color, edge_radius: float = 0.007):
	for i in points.size():
		for j in range(i + 1, points.size()):
			if points[i].distance_to(points[j]) < threshold:
				_create_edge(points[i], points[j], edge_radius, color)


# ═══════════════════════════════════════════
# MODE 0 — Flower of Life 3D
# Orbs distributed across stacked concentric rings
# forming a 3D spherical mandala
# ═══════════════════════════════════════════
func _create_flower_of_life_3d():
	# Central sun
	_create_vertex(Vector3.ZERO, 0.15, Color(1, 0.9, 0.5))

	# Ring 1: 6 equatorial orbs
	var ring1_colors = [
		Color(0.2, 0.8, 1), Color(1, 0.3, 0.6), Color(0.3, 1, 0.5),
		Color(1, 0.7, 0.2), Color(0.7, 0.3, 1), Color(0.2, 1, 0.8)
	]
	var ring1_pts = []
	for i in 6:
		var a = i * PI / 3.0
		var p = Vector3(cos(a), 0, sin(a)) * 0.9
		ring1_pts.append(p)
		_create_vertex(p, 0.08, ring1_colors[i])
	_connect_vertices(ring1_pts + [Vector3.ZERO], 1.1, Color(0.35, 0.65, 1), 0.005)

	# Ring 2: 12 orbs at lat ~20°
	var ring2_pts = []
	var lat2 = 0.35
	for i in 12:
		var a = i * PI / 6.0
		var p = Vector3(cos(a) * cos(lat2), sin(lat2), sin(a) * cos(lat2)) * 1.7
		ring2_pts.append(p)
		_create_vertex(p, 0.05, Color(0.45, 0.55, 1.0))
	for i in ring1_pts.size():
		for j in ring2_pts.size():
			if ring1_pts[i].distance_to(ring2_pts[j]) < 1.25:
				_create_edge(ring1_pts[i], ring2_pts[j], 0.004, Color(0.35, 0.25, 0.6))

	# Ring 3: 8 above + 8 below
	var ring3_pts = []
	for sgn in [-1, 1]:
		for i in 8:
			var a = i * TAU / 8.0
			var lat = sgn * 1.0
			var p = Vector3(cos(a) * cos(lat), sin(lat), sin(a) * cos(lat)) * 2.2
			ring3_pts.append(p)
			_create_vertex(p, 0.035, Color(0.75, 0.35, 1.0))

	# Ring 4: outer crown at poles
	for sgn in [-1, 1]:
		for i in 6:
			var a = i * TAU / 6.0
			var lat = sgn * 1.3
			var p = Vector3(cos(a) * cos(lat), sin(lat), sin(a) * cos(lat)) * 2.6
			_create_vertex(p, 0.03, Color(0.4, 0.7, 1.0))


# ═══════════════════════════════════════════
# MODE 1 — Metatron's Cube
# 13 nodes in cuboctahedron arrangement + all edges
# ═══════════════════════════════════════════
func _create_metatron_cube():
	var R = 2.2
	var points = [Vector3.ZERO]
	# 12 cuboctahedron vertices = FCC nearest neighbors
	var raw = []
	for s1 in [-1, 1]:
		for s2 in [-1, 1]:
			raw.append(Vector3(s1 * R, s2 * R, 0).normalized() * R)
			raw.append(Vector3(s1 * R, 0, s2 * R).normalized() * R)
			raw.append(Vector3(0, s1 * R, s2 * R).normalized() * R)
	var unique = []
	for v in raw:
		var dup = false
		for u in unique:
			if u.distance_to(v) < 0.01:
				dup = true; break
		if not dup: unique.append(v)
	points += unique

	for i in points.size():
		var col = Color(1, 0.85, 0.3) if i == 0 else Color(0.25, 0.7, 1.0)
		_create_vertex(points[i], 0.06 if i == 0 else 0.055, col)

	# Full Metatron — connect all to all
	_connect_vertices(points, 100.0, Color(0.25, 0.45, 1.0), 0.005)


# ═══════════════════════════════════════════
# MODE 2 — Platonic Solids
# ═══════════════════════════════════════════
func _get_platonic(index: int) -> Dictionary:
	var phi = 1.618033988749895
	match index:
		0:  # Tetrahedron
			var v2 = sqrt(2.0); var v6 = sqrt(6.0)
			var verts = PackedVector3Array([
				Vector3(0, 1, 0),
				Vector3(2*v2/3.0, -1.0/3.0, 0),
				Vector3(-v2/3.0, -1.0/3.0, v6/3.0),
				Vector3(-v2/3.0, -1.0/3.0, -v6/3.0),
			])
			return {"verts": verts, "thresh": 1.8, "color": Color(1, 0.25, 0.3)}
		1:  # Cube
			var v = 1.0 / sqrt(3.0)
			var verts = PackedVector3Array()
			for x in [-v, v]:
				for y in [-v, v]:
					for z in [-v, v]:
						verts.append(Vector3(x, y, z))
			return {"verts": verts, "thresh": 1.25, "color": Color(0.25, 1, 0.3)}
		2:  # Octahedron
			var verts = PackedVector3Array([
				Vector3(1,0,0), Vector3(-1,0,0),
				Vector3(0,1,0), Vector3(0,-1,0),
				Vector3(0,0,1), Vector3(0,0,-1),
			])
			return {"verts": verts, "thresh": 1.5, "color": Color(0.25, 0.5, 1)}
		3:  # Dodecahedron
			var iphi = 1.0 / phi
			var verts = PackedVector3Array([
				Vector3(1,1,1), Vector3(1,1,-1), Vector3(1,-1,1), Vector3(1,-1,-1),
				Vector3(-1,1,1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(-1,-1,-1),
				Vector3(0, iphi, phi), Vector3(0, iphi, -phi), Vector3(0, -iphi, phi), Vector3(0, -iphi, -phi),
				Vector3(iphi, phi, 0), Vector3(iphi, -phi, 0), Vector3(-iphi, phi, 0), Vector3(-iphi, -phi, 0),
				Vector3(phi, 0, iphi), Vector3(phi, 0, -iphi), Vector3(-phi, 0, iphi), Vector3(-phi, 0, -iphi),
			])
			for i in verts.size(): verts[i] = verts[i].normalized()
			return {"verts": verts, "thresh": 0.75, "color": Color(1, 0.65, 0.15)}
		4:  # Icosahedron
			var verts = PackedVector3Array([
				Vector3(0, 1, phi), Vector3(0, 1, -phi), Vector3(0, -1, phi), Vector3(0, -1, -phi),
				Vector3(1, phi, 0), Vector3(1, -phi, 0), Vector3(-1, phi, 0), Vector3(-1, -phi, 0),
				Vector3(phi, 0, 1), Vector3(phi, 0, -1), Vector3(-phi, 0, 1), Vector3(-phi, 0, -1),
			])
			for i in verts.size(): verts[i] = verts[i].normalized()
			return {"verts": verts, "thresh": 1.1, "color": Color(0.6, 0.15, 1)}
	return {}


func _create_platonic(index: int):
	var data = _get_platonic(index)
	if data.is_empty() or not data.has("verts"): return
	var verts: PackedVector3Array = data["verts"]
	var thresh: float = data.get("thresh", 1.5)
	var col: Color = data.get("color", Color(0.5, 0.5, 1.0))
	var scale = 2.5

	var points = []
	for v in verts:
		var p = v * scale
		points.append(p)
		_create_vertex(p, 0.08, col)
	_connect_vertices(points, thresh * scale, col, 0.006)


# ═══════════════════════════════════════════
# MODE 3 — Torus Knot
# ═══════════════════════════════════════════
func _create_torus_knot(p_val: int, q_val: int):
	var R = 2.2
	var r = 0.65
	var num = 160
	var points = []

	for i in num:
		var t = float(i) * TAU / num
		var phi_ang = p_val * t
		var x = (R + r * cos(q_val * t)) * cos(phi_ang)
		var y = r * sin(q_val * t)
		var z = (R + r * cos(q_val * t)) * sin(phi_ang)
		var pt = Vector3(x, y, z)
		points.append(pt)
		var hue = fmod(float(i) / num, 1.0)
		_create_vertex(pt, 0.035, Color.from_hsv(hue, 0.9, 1.0))

	for i in num:
		var j = (i + 1) % num
		var hue = fmod(float(i) / num, 1.0)
		_create_edge(points[i], points[j], 0.007, Color.from_hsv(hue, 0.8, 0.85))


# ═══════════════════════════════════════════
# MODE 4 — Fibonacci Golden Spiral in 3D
# ═══════════════════════════════════════════
func _create_fibonacci_spiral():
	var ga = PI * (3.0 - sqrt(5.0))  # golden angle
	var num = 180
	var max_r = 3.5
	var points = []

	for i in num:
		var t = float(i) / num
		var r_spiral = t * max_r
		var theta = i * ga
		var height = (t - 0.5) * 5.0
		var pt = Vector3(cos(theta) * r_spiral, height, sin(theta) * r_spiral)
		points.append(pt)
		var hue = fmod(t, 1.0)
		var sat = lerp(0.5, 1.0, t)
		_create_vertex(pt, 0.025 + t * 0.045, Color.from_hsv(hue, sat, 1.0))

	for i in points.size() - 1:
		var hue = fmod(float(i) / num, 1.0)
		_create_edge(points[i], points[i + 1], 0.005, Color.from_hsv(hue, 0.6, 0.8))


# ═══════════════════════════════════════════
# MODE 5 — Cymatics Sphere
# Grid of orbs on a sphere — standing wave nodes
# ═══════════════════════════════════════════
func _create_cymatics_sphere():
	var num_lat = 18
	var num_lon = 36
	var R = 2.5

	for la in num_lat:
		var lat = -PI/2.0 + (la + 1) * PI / (num_lat + 1)
		var ring_r = cos(lat) * R
		var h = sin(lat) * R
		for lo in num_lon:
			var lon = lo * TAU / num_lon
			var pt = Vector3(cos(lon) * ring_r, h, sin(lon) * ring_r)
			var hue = fmod(float(la) / num_lat + float(lo) / num_lon * 0.3, 1.0)
			_create_vertex(pt, 0.018, Color.from_hsv(hue, 0.6, 0.55))


# ═══════════════════════════════════════════
# MODE 6 — Merkaba (star tetrahedron)
# Two interlocking tetrahedra, one inverted, counter-rotating
# ═══════════════════════════════════════════
var merkaba_rot: float = 0.0

func _create_merkaba():
	merkaba_rot = 0.0
	var scale = 2.5
	# Tetrahedron 1 (upright) vertices
	var v2 = sqrt(2.0); var v6 = sqrt(6.0)
	var t1 = PackedVector3Array([
		Vector3(0, 1, 0),
		Vector3(2*v2/3.0, -1.0/3.0, 0),
		Vector3(-v2/3.0, -1.0/3.0, v6/3.0),
		Vector3(-v2/3.0, -1.0/3.0, -v6/3.0),
	])
	var pts1 = []
	for v in t1: pts1.append(v * scale)
	# Tetrahedron 2 (inverted — rotate 180° around Y)
	var pts2 = []
	for p in pts1: pts2.append(Vector3(-p.x, p.y, -p.z))

	for p in pts1: _create_vertex(p, 0.07, Color(0.3, 0.9, 1.0))
	for p in pts2: _create_vertex(p, 0.07, Color(1, 0.3, 0.8))
	_connect_vertices(pts1, 1.8 * scale, Color(0.25, 0.7, 1.0), 0.005)
	_connect_vertices(pts2, 1.8 * scale, Color(1, 0.25, 0.7), 0.005)
	# Cross-connections between the two tetrahedra
	for p1 in pts1:
		for p2 in pts2:
			if p1.distance_to(p2) < 2.0 * scale:
				_create_edge(p1, p2, 0.004, Color(0.6, 0.4, 1.0))


# ═══════════════════════════════════════════
# MODE 7 — Seed of Life
# 7 interlocking circles on equatorial plane
# ═══════════════════════════════════════════
func _create_seed_of_life():
	var R = 1.5
	var orbs_per_ring = 18
	# Center circle
	var center_pts = []
	for i in orbs_per_ring:
		var a = i * TAU / orbs_per_ring
		center_pts.append(Vector3(cos(a) * R, 0, sin(a) * R))
	for p in center_pts: _create_vertex(p, 0.04, Color(1, 0.85, 0.3))
	_connect_vertices(center_pts, R * 0.6, Color(1, 0.75, 0.2), 0.004)

	# 6 surrounding circles
	var colors = [Color(0.2,0.8,1), Color(1,0.3,0.6), Color(0.3,1,0.5),
				  Color(1,0.7,0.2), Color(0.7,0.3,1), Color(0.2,1,0.8)]
	for ring in 6:
		var cx = cos(ring * PI / 3.0) * R
		var cz = sin(ring * PI / 3.0) * R
		var ring_pts = []
		for i in orbs_per_ring:
			var a = i * TAU / orbs_per_ring
			ring_pts.append(Vector3(cx + cos(a) * R, 0, cz + sin(a) * R))
		for p in ring_pts: _create_vertex(p, 0.035, colors[ring])
		_connect_vertices(ring_pts, R * 0.6, colors[ring], 0.003)

	# Add depth — small orbs at Y offsets
	for sgn in [-1, 1]:
		for i in 6:
			var a = i * PI / 3.0
			var p = Vector3(cos(a) * R * 1.5, sgn * 0.6, sin(a) * R * 1.5)
			_create_vertex(p, 0.05, Color(0.5, 0.5, 1.0))


# ═══════════════════════════════════════════
# MODE 8 — Sri Yantra
# 9 interlocking triangles (4 up + 5 down), central bindu
# ═══════════════════════════════════════════
func _create_sri_yantra():
	# Central bindu
	_create_vertex(Vector3.ZERO, 0.1, Color(1, 0.9, 0.3))

	# 4 upward triangles (Shiva) + 5 downward triangles (Shakti)
	var all_tris = []
	var scales_up = [0.5, 1.0, 1.6, 2.3]
	var scales_dn = [0.75, 1.25, 1.85, 2.55, 3.0]
	var base_angle = 0.0

	# Upward triangles (pointing +Y)
	for i in scales_up.size():
		var s = scales_up[i]
		var angle = base_angle + i * PI / 9.0
		var pts = _make_triangle_points(s, angle, true, 0.1 * i)
		all_tris += pts
		var col = Color(1, 0.35, 0.2).lerp(Color(1, 0.8, 0.2), float(i) / scales_up.size())
		for p in pts: _create_vertex(p, 0.04, col)
		_connect_vertices(pts, s * 2.0, col, 0.005)

	# Downward triangles (pointing -Y)
	for i in scales_dn.size():
		var s = scales_dn[i]
		var angle = base_angle + PI / 6.0 + i * PI / 9.0
		var pts = _make_triangle_points(s, angle, false, 0.1 * i)
		all_tris += pts
		var col = Color(0.2, 0.5, 1.0).lerp(Color(0.6, 0.2, 1.0), float(i) / scales_dn.size())
		for p in pts: _create_vertex(p, 0.04, col)
		_connect_vertices(pts, s * 2.0, col, 0.005)

	# 8-petal lotus ring
	for i in 8:
		var a = i * TAU / 8.0
		var p = Vector3(cos(a) * 3.3, 0, sin(a) * 3.3)
		_create_vertex(p, 0.045, Color(1, 0.5, 0.8))

	# Outer square gate
	var sq_size = 3.6
	var sq_pts = [
		Vector3(-sq_size, -0.3, -sq_size), Vector3(sq_size, -0.3, -sq_size),
		Vector3(sq_size, -0.3, sq_size), Vector3(-sq_size, -0.3, sq_size),
	]
	for i in 4:
		_create_vertex(sq_pts[i], 0.035, Color(0.8, 0.6, 1.0))
		_create_edge(sq_pts[i], sq_pts[(i + 1) % 4], 0.004, Color(0.6, 0.4, 1.0))


func _make_triangle_points(scale: float, angle: float, up: bool, z_off: float) -> Array:
	var y_sign = 1.0 if up else -1.0
	var pts = [
		Vector3(0, y_sign * scale, z_off),
		Vector3(cos(-PI/6.0 + angle) * scale, y_sign * (-scale * 0.5), sin(-PI/6.0 + angle) * scale + z_off),
		Vector3(cos(PI * 7.0/6.0 + angle) * scale, y_sign * (-scale * 0.5), sin(PI * 7.0/6.0 + angle) * scale + z_off),
	]
	return pts


# ═══════════════════════════════════════════
# MODE 9 — Galaxy
# Multiple spiral arms with gradient orbs
# ═══════════════════════════════════════════
var galaxy_rot: float = 0.0

func _create_galaxy():
	galaxy_rot = 0.0
	var arms = galaxy_arms
	var orbs_per_arm = 45
	var max_r = 3.8
	var twist = 3.5  # how tightly wound

	for arm in arms:
		var arm_angle = arm * TAU / arms
		var arm_hue = fmod(float(arm) / arms, 1.0)
		var pts = []
		for i in orbs_per_arm:
			var t = float(i) / orbs_per_arm
			var r = t * max_r
			var angle = arm_angle + t * twist
			var height = (t - 0.5) * 0.8  # slight vertical rise
			var pt = Vector3(cos(angle) * r, height, sin(angle) * r)
			pts.append(pt)
			var hue = fmod(arm_hue + t * 0.3, 1.0)
			var sat = lerp(0.4, 1.0, t)
			_create_vertex(pt, 0.015 + t * 0.03, Color.from_hsv(hue, sat, 1.0))
		# Connect along arm
		for i in pts.size() - 1:
			_create_edge(pts[i], pts[i + 1], 0.004, Color.from_hsv(arm_hue, 0.6, 0.8))

	# Central core
	_create_vertex(Vector3.ZERO, 0.12, Color(1, 0.95, 0.7))
	var core_pts = []
	for i in 8:
		var a = i * TAU / 8.0
		var p = Vector3(cos(a), 0, sin(a)) * 0.25
		core_pts.append(p)
		_create_vertex(p, 0.04, Color(1, 0.8, 0.3))
	_connect_vertices(core_pts + [Vector3.ZERO], 0.4, Color(1, 0.7, 0.2), 0.005)


# ═══════════════════════════════════════════
# MODE 10 — Cosmic Rivers
# Flowing energy streams along sacred geometry paths
# ═══════════════════════════════════════════
func _create_cosmic_rivers():
	var num_streams = 9
	var pts_per_stream = 30
	var radius = 3.0
	var colors_hue = [0.55, 0.7, 0.85, 0.0, 0.15, 0.35, 0.5, 0.65, 0.8]

	for s in num_streams:
		var base_angle = s * TAU / num_streams
		var stream_pts = []
		for i in pts_per_stream:
			var t = float(i) / pts_per_stream
			var a = base_angle + sin(t * TAU * 2.0) * 0.5
			var r = radius * (0.3 + t * 0.7)
			var h = sin(t * TAU * 1.5) * 2.5
			var pt = Vector3(cos(a) * r, h, sin(a) * r)
			stream_pts.append(pt)
			var sat = 0.5 + t * 0.5
			var val = 0.6 + t * 0.4
			_create_vertex(pt, 0.025 + t * 0.015, Color.from_hsv(colors_hue[s], sat, val))
		for i in stream_pts.size() - 1:
			_create_edge(stream_pts[i], stream_pts[i + 1], 0.005, Color(0.3, 0.5, 1.0, 0.6))
	# Central pulsing core
	for l in 5:
		var lat = lerp(-1.0, 1.0, float(l) / 4.0)
		for lo in 8:
			var lon = lo * TAU / 8.0
			var r = cos(lat) * 0.8
			_create_vertex(Vector3(cos(lon)*r, sin(lat)*0.8, sin(lon)*r), 0.04, Color(0.6, 0.7, 1.0))


# ═══════════════════════════════════════════
# MAIN PROCESS LOOP
# ═══════════════════════════════════════════
func _process(delta):
	delta *= speed_mult
	if Input.is_key_pressed(KEY_SHIFT):
		delta *= 0.15
	time += delta

	# Simulated playback for MovieWriter recording
	var t = 0.0
	if audio.playing:
		t = audio.get_playback_position()
	else:
		if not recording:
			recording = true
			record_duration = 199.0
			record_start = 0.0
		simulated_time += delta
		t = simulated_time

	# Clean exit when recording reaches song length
	if recording and simulated_time >= record_duration:
		get_tree().quit()

	# ── Process replay events ──
	if replaying and replay_index < replay_events.size():
		while replay_index < replay_events.size():
			var ev = replay_events[replay_index]
			if ev["time"] > t: break
			if ev["pressed"]:
				_handle_key(ev["keycode"])
			replay_index += 1

	var feat = {"onset": 0, "rms": 0.5, "centroid": 0.5}
	if dance_data: feat = dance_data.feat_at(t)

	var amp = feat["rms"] * 2.5
	var onset_val = feat["onset"]
	var centroid = feat["centroid"]

	# Beat energy — smoothed onset for punchy transients
	beat_energy = lerp(beat_energy, onset_val * 3.5, delta * 9.0)

	# ── Animate vertex orbs ──
	for orb in vertex_orbs:
		var node: Node3D = orb["node"]
		var phase: float = orb["phase"]
		var base_pos: Vector3 = orb["base_pos"]

		# Cymatics mode: radial breathing by spherical harmonic
		if mode == 5:
			var r = base_pos.length()
			if r > 0.01:
				var lat = asin(clampf(base_pos.y / r, -1.0, 1.0))
				var lon = atan2(base_pos.z, base_pos.x)
				var wave = sin(lat * 5.0 + time * 3.0 + centroid * 2.0) * cos(lon * 3.0 + time * 2.0)
				wave = wave * 0.5 + 0.5
				var displ = base_pos.normalized() * wave * 0.6 * (0.5 + amp)
				node.position = base_pos + displ
			else:
				node.position = base_pos
		elif mode == 3:
			var wobble = sin(time * 4.0 + phase * 3.0) * 0.04 * (1.0 + beat_energy)
			node.position = base_pos + Vector3(wobble, wobble * 0.7, wobble * 0.5)
		elif mode == 4:
			var w = sin(time * 2.5 + base_pos.length() * 1.5) * 0.06 * (1.0 + beat_energy)
			node.position = base_pos + Vector3(w * 0.5, w, w * 0.5)
		else:
			node.position = base_pos  # reset any prior displacement

		# Universal pulse — gentler, never disruptive
		var pulse = 0.85 + amp * 0.5 + beat_energy * 0.8 * (sin(time * 6.0 + phase) * 0.5 + 0.5)
		node.scale = Vector3.ONE * pulse * 2.5

		# ── 16M Color System — procedural uniqueness per orb ──
		var pal_hue = PALETTE_HUES[palette_index]
		var pal_sat = PALETTE_SATS[palette_index]
		var pal_val = PALETTE_VALS[palette_index]
		# Seed from music: centroid (pitch), onset (rhythm), time, and orb position
		var color_seed = centroid * 3.7 + onset_val * 2.3 + base_pos.x * 0.17 + base_pos.y * 0.13 + base_pos.z * 0.11 + phase * 0.07
		# Gradient descent: slowly shift toward a target hue based on music
		var target_hue = fmod(pal_hue + color_seed + time * 0.03, 1.0)
		var current_hue = orb.get("color_hue", target_hue)
		current_hue = lerpf(current_hue, target_hue, delta * 0.8)
		orb["color_hue"] = current_hue
		var sat = clampf(pal_sat * (0.6 + centroid * 0.4 + onset_val * 0.2), 0.15, 1.0)
		var val = clampf(pal_val * (0.5 + amp * 0.4 + phase * 0.1), 0.3, 1.0)
		var ec = Color.from_hsv(current_hue, sat, val)
		var brightness = 1.1 + amp * 1.2 + beat_energy * 2.0
		node.material_override.set_shader_parameter("albedo", ec)
		node.material_override.set_shader_parameter("base_brightness", brightness)
		node.material_override.set_shader_parameter("beat", beat_energy * 0.6)

	# ── Animate edges ──
	for edge in edge_nodes:
		var mat: ShaderMaterial = edge.material_override
		if mat:
			mat.set_shader_parameter("brightness", 0.25 + amp * 1.2 + beat_energy * 1.5)

	# ── Mode-specific rotation ──
	if mode == 6:  # Merkaba counter-rotation
		merkaba_rot += delta * (0.4 + amp * 0.8)
		for i in vertex_orbs.size():
			var orb = vertex_orbs[i]
			var bp: Vector3 = orb["base_pos"]
			if i < 4:  # First tetrahedron
				orb["node"].position = bp.rotated(Vector3.UP, merkaba_rot)
			else:  # Second tetrahedron — counter-rotate
				orb["node"].position = bp.rotated(Vector3.UP, -merkaba_rot * 0.7)
	elif mode == 9:  # Galaxy rotation
		galaxy_rot += delta * (0.2 + amp * 0.4)
		geometry_container.rotate_y(delta * (0.2 + amp * 0.4))

	# ── Energy rivers ──
	if rivers_visible and river_data.size() > 0:
		_update_rivers(amp, beat_energy, delta)

	# ── Starfield pulse ──
	if starfield:
		starfield.speed_scale = 0.3 + amp * 0.8
		var spm: ParticleProcessMaterial = starfield.process_material as ParticleProcessMaterial
		if spm:
			var sc = Color(0.5 + amp, 0.6 + amp * 1.2, 1.0)
			spm.color = sc

	# ── Grid cage ──
	if cage_visible and grid_cage:
		grid_cage.visible = true
		grid_cage.rotate_y(delta * 0.06)
		grid_cage.rotate_x(delta * 0.03)
	elif grid_cage:
		grid_cage.visible = false

	# ── Celestial light pulse (rare, gentle) ──
	if onset_val > 0.6 and beat_energy > 1.5:
		_create_blast()
		beat_energy *= 0.5  # dampen so it doesn't chain

	# ── Camera orbit ──
	if auto_orbit:
		cam_theta += delta * (0.18 + amp * 0.35)
		cam_phi += sin(time * 0.25) * delta * 0.08
	cam_phi = clamp(cam_phi, -1.4, 1.4)
	cam_radius = 7.0 + sin(time * 0.6) * 1.8 - beat_energy * 2.5
	cam_radius = clamp(cam_radius, 3.0, 15.0)
	_update_camera_position()

	# ── HUD ──
	var label = get_node_or_null("Label")
	if label:
		var mn = MODE_NAMES[mode]
		if mode == 2: mn += ": " + PLATONIC_NAMES[platonic_index]
		if mode == 3: mn += " (%d,%d)" % [torus_p, torus_q]
		label.text = "%s   %s%.1fs   e:%.2f   %.2f×   [%s]" % [mn, "✦ " if beat_energy > 0.5 else "", t, amp, speed_mult, PALETTE_NAMES[palette_index]]
		if not auto_orbit:
			label.text += "   [free]"
		if Input.is_key_pressed(KEY_SHIFT):
			label.text += "   [slow]"
		if cage_visible:
			label.text += "   [cage]"
		if not rivers_visible:
			label.text += "   [no rivers]"
		if input_recording:
			label.text += "   ●REC(%d)" % input_events.size()
		if replaying:
			label.text += "   ▶REPLAY(%d/%d)" % [replay_index, replay_events.size()]


# ═══════════════════════════════════════════
# INPUT — play the geometries like an instrument
# ═══════════════════════════════════════════
func _input(event: InputEvent):
	# ── Record input for replay ──
	if input_recording and event is InputEventKey:
		var t = audio.get_playback_position() if audio.playing else simulated_time
		input_events.append({"time": t, "keycode": event.keycode, "pressed": event.pressed})

	if event is InputEventKey and event.pressed:
		_handle_key(event.keycode)

	if not replaying:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed: mouse_dragging = true; mouse_last = event.position; auto_orbit = false
				else:
					mouse_dragging = false
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP: cam_radius = maxf(cam_radius - 0.5, 2.0); auto_orbit = false
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam_radius = minf(cam_radius + 0.5, 18.0); auto_orbit = false
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed: auto_orbit = not auto_orbit
		elif event is InputEventMouseMotion and mouse_dragging:
			var dm = event.position - mouse_last; mouse_last = event.position
			cam_theta -= dm.x * 0.005; cam_phi += dm.y * 0.005; cam_phi = clamp(cam_phi, -1.4, 1.4)


func _handle_key(keycode: int):
	match keycode:
		KEY_TAB: _cycle_mode(); return
		KEY_SPACE: beat_energy = 3.0; return
		KEY_1: _jump_mode(0); return
		KEY_2: _jump_mode(1); return
		KEY_3: _jump_mode(2); return
		KEY_4: _jump_mode(3); return
		KEY_5: _jump_mode(4); return
		KEY_6: _jump_mode(5); return
		KEY_7: _jump_mode(6); return
		KEY_8: _jump_mode(7); return
		KEY_9: _jump_mode(8); return
		KEY_0: _jump_mode(9); return
		KEY_BACKSLASH: _jump_mode(10); return
		KEY_K:
			input_recording = not input_recording
			if input_recording: input_events.clear()
			else: _save_replay()
			return
		KEY_V:
			recording = true; record_duration = 180.0; record_start = simulated_time
			return
		KEY_R:
			if mode == 2: platonic_index = randi() % 5
			elif mode == 3: torus_p = randi() % 10 + 1; torus_q = randi() % 10 + 1
			_build_current_geometry(); return
		KEY_M: mouse_cam = not mouse_cam; auto_orbit = mouse_cam; return
		KEY_C: palette_index = (palette_index + 1) % PALETTE_NAMES.size(); return
		KEY_G: cage_visible = not cage_visible; return
		KEY_H:
			rivers_visible = not rivers_visible
			if not rivers_visible:
				_clear_river_motes()
			else:
				_build_river_data()
			return
		KEY_E:
			if mode == 9: galaxy_arms = clampi(galaxy_arms + 1, 2, 8); _build_current_geometry()
			return
		KEY_B: env_ref.glow_enabled = not env_ref.glow_enabled; return
		KEY_F:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		KEY_UP:
			if mode == 3:
				torus_p = clampi(torus_p + 1, 1, 12); _build_current_geometry()
			else:
				speed_mult = minf(speed_mult + 0.05, 3.0)
			return
		KEY_DOWN:
			if mode == 3:
				torus_p = clampi(torus_p - 1, 1, 12); _build_current_geometry()
			else:
				speed_mult = maxf(speed_mult - 0.05, 0.05)
			return
		KEY_RIGHT, KEY_PERIOD:
			if mode == 2: platonic_index = (platonic_index + 1) % 5; _build_current_geometry()
			elif mode == 3: torus_q = clampi(torus_q + 1, 1, 12); _build_current_geometry()
			return
		KEY_LEFT, KEY_COMMA:
			if mode == 2: platonic_index = (platonic_index - 1) % 5; _build_current_geometry()
			elif mode == 3: torus_q = clampi(torus_q - 1, 1, 12); _build_current_geometry()
			return
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: speed_mult = minf(speed_mult + 0.05, 3.0); return
		KEY_MINUS, KEY_KP_SUBTRACT: speed_mult = maxf(speed_mult - 0.05, 0.05); return
		KEY_PAGEDOWN: speed_mult = maxf(speed_mult - 0.5, 0.05); return
		KEY_PAGEUP: speed_mult = minf(speed_mult + 0.5, 3.0); return


func _jump_mode(m: int):
	if mode == m: return
	mode = m
	_build_current_geometry()


func _cycle_mode():
	mode = (mode + 1) % MODE_NAMES.size()
	_build_current_geometry()


# ═══════════════════════════════════════════
# INPUT REPLAY — save/load
# ═══════════════════════════════════════════


# ═══════════════════════════════════════════
# STARFIELD — cosmic background particles
# ═══════════════════════════════════════════
func _create_starfield():
	starfield = GPUParticles3D.new()
	starfield.name = "Starfield"
	starfield.emitting = true
	starfield.amount = 400
	starfield.lifetime = 8.0
	starfield.one_shot = false
	starfield.explosiveness = 0.0
	starfield.speed_scale = 0.3
	starfield.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))

	# Emission shape — large box
	var box = BoxShape3D.new()
	box.extents = Vector3(10, 10, 10)
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12, 12, 12)
	pm.direction = Vector3(0, 0, 0)  # spread
	pm.spread = 180.0
	pm.gravity = Vector3(0, 0, 0)
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.scale_min = 0.015
	pm.scale_max = 0.05
	pm.color = Color(0.7, 0.8, 1.0)
	starfield.process_material = pm

	var draw_pass = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.03; sphere.height = 0.06
	sphere.radial_segments = 4; sphere.rings = 2
	draw_pass.mesh = sphere
	var sm = StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color.WHITE
	sm.emission_enabled = true
	sm.emission = Color(0.8, 0.85, 1.0)
	draw_pass.material_override = sm
	starfield.draw_pass_1 = draw_pass

	add_child(starfield)
	# Move starfield behind geometry in draw order
	move_child(starfield, 0)


# ═══════════════════════════════════════════
# GRID CAGE — real wireframe icosahedron + dodecahedron
# ═══════════════════════════════════════════
func _create_grid_cage():
	grid_cage = Node3D.new()
	grid_cage.name = "GridCage"
	grid_cage.visible = false
	add_child(grid_cage)

	# Icosahedron cage — 12 vertices, 30 edges
	var ico_verts = _get_platonic(4)["verts"]  # Icosahedron
	var ico_pts = []
	var scale_ico = 5.0
	for v in ico_verts:
		var p = v * scale_ico
		ico_pts.append(p)
		_cage_vertex(grid_cage, p, 0.03, Color(0.3, 0.6, 1.0))
	for i in ico_pts.size():
		for j in range(i + 1, ico_pts.size()):
			if ico_pts[i].distance_to(ico_pts[j]) < 1.2 * scale_ico:
				_cage_edge(grid_cage, ico_pts[i], ico_pts[j], 0.004, Color(0.25, 0.5, 1.0, 0.6))

	# Dodecahedron cage — 20 vertices, 30 edges
	var dod_verts = _get_platonic(3)["verts"]  # Dodecahedron
	var dod_pts = []
	var scale_dod = 5.8
	for v in dod_verts:
		var p = v * scale_dod
		dod_pts.append(p)
		_cage_vertex(grid_cage, p, 0.025, Color(0.6, 0.3, 1.0))
	for i in dod_pts.size():
		for j in range(i + 1, dod_pts.size()):
			if dod_pts[i].distance_to(dod_pts[j]) < 0.8 * scale_dod:
				_cage_edge(grid_cage, dod_pts[i], dod_pts[j], 0.003, Color(0.5, 0.25, 1.0, 0.5))


func _cage_vertex(parent: Node3D, pos: Vector3, r: float, col: Color):
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = r; sphere.height = r * 2.0
	sphere.radial_segments = 8; sphere.rings = 4
	mesh.mesh = sphere; mesh.position = pos
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.5)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.6
	mesh.material_override = mat
	parent.add_child(mesh)


func _cage_edge(parent: Node3D, fr: Vector3, to: Vector3, radius: float, col: Color):
	var dir_vec = to - fr
	var length = dir_vec.length()
	if length < 0.001: return
	var mid = (fr + to) / 2.0
	var mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius; cyl.bottom_radius = radius
	cyl.height = length; cyl.radial_segments = 4; cyl.rings = 1
	mesh.mesh = cyl; mesh.position = mid
	var y_ax = Vector3.UP; var tgt = dir_vec.normalized()
	var dot = y_ax.dot(tgt)
	if dot < -0.9999: mesh.rotation = Vector3(1, 0, 0) * PI
	elif dot < 0.9999: mesh.rotate(y_ax.cross(tgt).normalized(), y_ax.angle_to(tgt))
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.4
	mesh.material_override = mat
	parent.add_child(mesh)


# ═══════════════════════════════════════════
# ENERGY RIVERS — motes flowing along every edge
# ═══════════════════════════════════════════
func _build_river_data():
	river_data.clear()
	for edge in edge_nodes:
		var mesh: MeshInstance3D = edge
		var cyl: CylinderMesh = mesh.mesh
		var length = cyl.height
		var half = length / 2.0
		# Cylinder extends along local Y, rotated to world by mesh.rotation
		var local_top = Vector3(0, half, 0)
		var local_bot = Vector3(0, -half, 0)
		var fr = mesh.to_global(local_bot)
		var to = mesh.to_global(local_top)
		river_data.append({"fr": fr, "to": to, "length": length, "motes": []})
	_spawn_river_motes()


func _spawn_river_motes():
	_clear_river_motes()
	for rd in river_data:
		var num = clampi(int(rd["length"] / 0.8), 1, 4)
		for _k in num:
			var t = randf()
			var pos = rd["fr"].lerp(rd["to"], float(t))
			var dir = 1.0 if randf() > 0.5 else -1.0
			var mesh = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.012; sphere.height = 0.024
			sphere.radial_segments = 4; sphere.rings = 2
			mesh.mesh = sphere; mesh.position = pos
			var mat = orb_shader.duplicate()
			mat.set_shader_parameter("albedo", Color(0.5, 0.8, 1.0))
			mat.set_shader_parameter("base_brightness", 2.5)
			mat.set_shader_parameter("fresnel_power", 1.2)
			mesh.material_override = mat
			geometry_container.add_child(mesh)
			rd["motes"].append({"node": mesh, "t": t, "dir": dir, "speed": randf_range(0.3, 0.9)})
			river_motes.append(mesh)


func _clear_river_motes():
	for motes in river_data:
		for m in motes.get("motes", []):
			m["node"].queue_free()
	for m in river_motes:
		m.queue_free()
	river_motes.clear()
	for rd in river_data:
		rd["motes"] = []


func _update_rivers(amp: float, beat_e: float, delta: float):
	for rd in river_data:
		var fr: Vector3 = rd["fr"]
		var to: Vector3 = rd["to"]
		for m in rd["motes"]:
			var node: MeshInstance3D = m["node"]
			var spd = m["speed"] * (0.5 + amp * 2.0 + beat_e * 2.0)
			m["t"] += m["dir"] * spd * delta
			if m["t"] > 1.0:
				m["t"] = 1.0; m["dir"] = -1.0
			elif m["t"] < 0.0:
				m["t"] = 0.0; m["dir"] = 1.0
			node.position = fr.lerp(to, float(m["t"]))
			var mat: ShaderMaterial = node.material_override
			if mat:
				var hue = fmod(time * 0.1 + float(m["t"]), 1.0)
				mat.set_shader_parameter("albedo", Color.from_hsv(hue, 0.9, 1.0))
				mat.set_shader_parameter("base_brightness", 1.8 + amp * 2.0 + beat_e * 2.0)


# ═══════════════════════════════════════════
# BEAT BLAST — particle burst in 3D
# ═══════════════════════════════════════════
func _create_blast():
	var origin = Vector3.ZERO
	if vertex_orbs.size() > 0:
		var idx = randi() % vertex_orbs.size()
		origin = vertex_orbs[idx]["node"].position
	for _k in range(16):
		var pos = origin + Vector3(
			randf_range(-1.5, 1.5),
			randf_range(-1.5, 1.5),
			randf_range(-1.5, 1.5)
		)
		var mesh = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.04; sphere.height = 0.08
		mesh.mesh = sphere; mesh.position = pos
		var mat = orb_shader.duplicate()
		var bc = Color(1, 0.75, 0.25)
		mat.set_shader_parameter("albedo", bc)
		mat.set_shader_parameter("base_brightness", 3.0)
		mat.set_shader_parameter("fresnel_power", 1.5)
		mesh.material_override = mat
		add_child(mesh)
		var timer = get_tree().create_timer(0.35)
		timer.timeout.connect(func(): mesh.queue_free())


# ═══════════════════════════════════════════
# INPUT REPLAY — record your performance, replay for video
# ═══════════════════════════════════════════
func _save_replay():
	var data = {"events": input_events}
	var f = FileAccess.open(replay_file, FileAccess.WRITE)
	if not f:
		DirAccess.make_dir_recursive_absolute(replay_file.get_base_dir())
		f = FileAccess.open(replay_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		input_recording = false


func _load_replay():
	if not FileAccess.file_exists(replay_file): return
	var f = FileAccess.open(replay_file, FileAccess.READ)
	var j = JSON.new(); j.parse(f.get_as_text())
	var d = j.get_data()
	replay_events = d.get("events", [])
	if replay_events.size() > 0:
		# Normalize timestamps — start from first event
		var offset = replay_events[0]["time"]
		for ev in replay_events:
			ev["time"] = ev["time"] - offset
		simulated_time = 0.0
		replaying = true
		recording = true
		record_duration = 199.0
