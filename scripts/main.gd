extends Node3D

# ── Audio ──
var audio: AudioStreamPlayer
var dance_data: DanceData
var time: float = 0.0
var beat_energy: float = 0.0
var speed_mult: float = 1.0

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

const MODE_NAMES = [
	"Flower of Life 3D",
	"Metatron's Cube",
	"Platonic Solids",
	"Torus Knot",
	"Fibonacci Spiral",
	"Cymatics Sphere"
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
			"onset": onset[i] if i < onset.size() else 0,
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

	# Two-tone directional lights for depth
	var dl1 = DirectionalLight3D.new()
	dl1.position = Vector3(5, 8, 5)
	dl1.light_energy = 0.35
	dl1.light_color = Color(0.3, 0.2, 0.5)
	add_child(dl1)

	var dl2 = DirectionalLight3D.new()
	dl2.position = Vector3(-4, -3, -5)
	dl2.light_energy = 0.2
	dl2.light_color = Color(0.1, 0.3, 0.6)
	add_child(dl2)

	# Environment — deep void with rich glow
	var env = WorldEnvironment.new()
	var er = Environment.new()
	er.background_color = Color(0.02, 0.01, 0.04, 1)
	er.ambient_light_color = Color(0.06, 0.03, 0.12, 1)
	er.ambient_light_source = 1
	er.glow_enabled = true
	er.glow_intensity = 2.8
	er.glow_bloom = 0.7
	er.glow_hdr_threshold = 0.75
	env.environment = er
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


func _build_current_geometry():
	_clear_geometry()
	match mode:
		0: _create_flower_of_life_3d()
		1: _create_metatron_cube()
		2: _create_platonic(platonic_index)
		3: _create_torus_knot(torus_p, torus_q)
		4: _create_fibonacci_spiral()
		5: _create_cymatics_sphere()


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
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 3.2
	mat.emission_energy_multiplier = 1.6
	mesh.material_override = mat
	geometry_container.add_child(mesh)
	var orb = {
		"node": mesh,
		"base_radius": radius,
		"color": color,
		"phase": randf() * TAU,
		"base_pos": pos  # original position for displacement-based animations
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

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color * 0.4
	mat.emission_enabled = true
	mat.emission = color * 1.8
	mat.emission_energy_multiplier = 1.0
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
	var verts: PackedVector3Array = data["verts"]
	var thresh: float = data["thresh"]
	var col: Color = data["color"]
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
# MAIN PROCESS LOOP
# ═══════════════════════════════════════════
func _process(delta):
	delta *= speed_mult
	if Input.is_key_pressed(KEY_SHIFT):
		delta *= 0.15
	time += delta
	if not audio.playing: return

	var t = audio.get_playback_position()
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

		# Universal pulse
		var pulse = 1.0 + amp * 1.0 + beat_energy * 1.6 * (sin(time * 8.0 + phase) * 0.5 + 0.5)
		node.scale = Vector3.ONE * pulse * 2.8

		# Color shift — centroid drives hue drift
		var hue = fmod(centroid * 0.25 + time * 0.07 + phase * 0.15, 1.0)
		var ec = Color.from_hsv(hue, 0.85, 1.0)
		node.material_override.emission = ec * (2.0 + amp * 3.5 + beat_energy * 5.5)
		node.material_override.albedo_color = ec * 0.25

	# ── Animate edges ──
	for edge in edge_nodes:
		var mat: StandardMaterial3D = edge.material_override
		if mat:
			mat.emission_energy_multiplier = 0.4 + amp * 2.0 + beat_energy * 3.0

	# ── Beat blast ──
	if onset_val > 0.3 and beat_energy > 1.0:
		_create_blast()

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
		label.text = "%s   %s%.1fs   e:%.2f   %.2f×" % [mn, "✦ " if beat_energy > 0.5 else "", t, amp, speed_mult]
		if not auto_orbit:
			label.text += "   [free cam]"
		if Input.is_key_pressed(KEY_SHIFT):
			label.text += "   [slow]"


# ═══════════════════════════════════════════
# INPUT — play the geometries like an instrument
# ═══════════════════════════════════════════
func _input(event: InputEvent):
	# ── Keyboard ──
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_cycle_mode()
				return
			KEY_SPACE:
				_create_blast()
				beat_energy = 2.0  # surge
				return
			KEY_1: _jump_mode(0); return
			KEY_2: _jump_mode(1); return
			KEY_3: _jump_mode(2); return
			KEY_4: _jump_mode(3); return
			KEY_5: _jump_mode(4); return
			KEY_6: _jump_mode(5); return
			KEY_R:
				if mode == 2:
					platonic_index = randi() % 5
				elif mode == 3:
					torus_p = randi() % 10 + 1
					torus_q = randi() % 10 + 1
				_build_current_geometry()
				return
			KEY_M:
				mouse_cam = not mouse_cam
				auto_orbit = mouse_cam
				return
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
				if mode == 2:
					platonic_index = (platonic_index + 1) % 5; _build_current_geometry()
				elif mode == 3:
					torus_q = clampi(torus_q + 1, 1, 12); _build_current_geometry()
				return
			KEY_LEFT, KEY_COMMA:
				if mode == 2:
					platonic_index = (platonic_index - 1) % 5; _build_current_geometry()
				elif mode == 3:
					torus_q = clampi(torus_q - 1, 1, 12); _build_current_geometry()
				return
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				speed_mult = minf(speed_mult + 0.05, 3.0); return
			KEY_MINUS, KEY_KP_SUBTRACT:
				speed_mult = maxf(speed_mult - 0.05, 0.05); return
			KEY_PAGEDOWN:
				speed_mult = maxf(speed_mult - 0.5, 0.05); return
			KEY_PAGEUP:
				speed_mult = minf(speed_mult + 0.5, 3.0); return

	# ── Mouse drag — free orbit ──
	if not mouse_cam: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				mouse_dragging = true
				mouse_last = event.position
				auto_orbit = false
			else:
				mouse_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_radius = maxf(cam_radius - 0.5, 2.0)
			auto_orbit = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_radius = minf(cam_radius + 0.5, 18.0)
			auto_orbit = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			auto_orbit = not auto_orbit
	elif event is InputEventMouseMotion and mouse_dragging:
		var delta_m = event.position - mouse_last
		mouse_last = event.position
		cam_theta -= delta_m.x * 0.005
		cam_phi += delta_m.y * 0.005
		cam_phi = clamp(cam_phi, -1.4, 1.4)


func _jump_mode(m: int):
	if mode == m: return
	mode = m
	_build_current_geometry()


func _cycle_mode():
	mode = (mode + 1) % MODE_NAMES.size()
	_build_current_geometry()


# ═══════════════════════════════════════════
# BEAT BLAST — particle burst in 3D
# ═══════════════════════════════════════════
func _create_blast():
	var origin = Vector3.ZERO
	if vertex_orbs.size() > 0:
		var idx = randi() % vertex_orbs.size()
		origin = vertex_orbs[idx]["node"].position
	for _k in range(14):
		var pos = origin + Vector3(
			randf_range(-1.2, 1.2),
			randf_range(-1.2, 1.2),
			randf_range(-1.2, 1.2)
		)
		var mesh = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.04; sphere.height = 0.08
		mesh.mesh = sphere; mesh.position = pos
		var mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = Color(1, 0.75, 0.25) * 7.0
		mesh.material_override = mat
		add_child(mesh)
		var timer = get_tree().create_timer(0.35)
		timer.timeout.connect(func(): mesh.queue_free())
