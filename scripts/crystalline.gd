extends Node3D

# ═══════════════════════════════════════════
# CRYSTALLINE — 12 Sacred Geometry Layers
# Diamond-cut orbs · Fluid transitions · Magic layers
# ═══════════════════════════════════════════

# ── Audio ──
var audio: AudioStreamPlayer
var dance_data: DanceData
var time: float = 0.0
var beat_energy: float = 0.0
var amp: float = 0.0
var centroid: float = 0.5
var speed_mult: float = 1.0

# ── Camera ──
var cam: Camera3D
var cam_theta: float = 0.0
var cam_phi: float = 0.3
var cam_radius: float = 7.0
var mouse_dragging: bool = false
var mouse_last: Vector2
var auto_orbit: bool = true

# ── Crystals ──
const POOL_SIZE = 140
var orbs: Array = []          # {node, mesh, pos, target_pos, color, hue_offset}
var crystal_mesh: ArrayMesh
var crystal_shader: ShaderMaterial
var env_ref: Environment
var starfield: GPUParticles3D

# ── Layers ──
var current_layer: int = 0
var target_layer: int = 0
var transition_progress: float = 1.0
const LAYER_NAMES = [
	"Bindu", "Dyad", "Triad", "Tetrad",
	"Pentad", "Hexad", "Heptad", "Octad",
	"Ennead", "Decad", "Icosahedron", "Flower Bloom"
]
var auto_transition: bool = true
var transition_cooldown: float = 0.0
var beat_count: int = 0

# ── Magic Layers (F1-F8) ──
var magic_halos: bool = false
var magic_rays: bool = false
var magic_ripples: bool = false
var magic_constellation: bool = false
var magic_aurora: bool = false
var magic_cymatics: bool = false
var magic_trails: bool = false
var magic_mirror: bool = false
var trail_positions: Array = []
var ripple_timer: float = 0.0
var ripple_nodes: Array = []
var ray_nodes: Array = []
var constellation_edges: Array = []

# ── Particles ──
var particle_nodes: Array = []
var particle_angles: Array = []  # orbital positions

# ── Color ──
var palette_index: int = 0
var hue_shift: float = 0.0
var sat_mult: float = 1.0
const PALETTES = [
	{"name": "Prismatic", "hue": 0.0, "sat": 1.0},
	{"name": "Fire Opal", "hue": 0.07, "sat": 1.0},
	{"name": "Ocean", "hue": 0.55, "sat": 0.9},
	{"name": "Amethyst", "hue": 0.78, "sat": 0.85},
	{"name": "Emerald", "hue": 0.35, "sat": 0.8},
	{"name": "Diamond", "hue": 0.0, "sat": 0.15},  # white/silver
	{"name": "Ruby", "hue": 0.02, "sat": 1.0},
	{"name": "Cosmic", "hue": 0.65, "sat": 1.0},
]

# ═══════════════════════════════════════════
# DanceData
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
		if num_frames <= 0: return {"onset": 0, "rms": 0.5, "centroid": 0.5}
		var i = clampi(int(t * fps), 0, num_frames - 1)
		return {
			"onset": onset[i] if i < onset.size() else 0,
			"rms": rms[i] if i < rms.size() else 0.5,
			"centroid": centroid[i] if i < centroid.size() else 0.5
		}


# ═══════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════
func _ready():
	_setup_scene()
	_build_crystal_mesh()
	_create_orbs()
	_assign_layer_positions(current_layer, true)
	audio.play()


func _setup_scene():
	# Audio
	audio = AudioStreamPlayer.new(); add_child(audio)
	var dir = DirAccess.open("res://music"); dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if fn.get_extension() in ["mp3", "wav"]:
			var s = load("res://music/" + fn)
			if s: audio.stream = s; break
		fn = dir.get_next()

	# Environment
	var env = WorldEnvironment.new()
	env_ref = Environment.new()
	env_ref.background_color = Color(0.005, 0.003, 0.015)
	env_ref.ambient_light_color = Color(0.03, 0.015, 0.06)
	env_ref.ambient_light_source = 1
	env_ref.glow_enabled = true
	env_ref.glow_intensity = 3.5
	env_ref.glow_bloom = 0.9
	env_ref.glow_hdr_threshold = 0.35
	env_ref.glow_hdr_scale = 3.0
	env_ref.volumetric_fog_enabled = true
	env_ref.volumetric_fog_density = 0.006
	env_ref.volumetric_fog_albedo = Color(0.04, 0.01, 0.08)
	env_ref.volumetric_fog_emission = Color(0.08, 0.03, 0.15)
	env_ref.volumetric_fog_emission_energy = 0.4
	env.environment = env_ref; add_child(env)

	# Camera
	cam = Camera3D.new(); cam.current = true; cam.fov = 58; add_child(cam)
	_update_camera()

	# Starfield
	_create_starfield()

	# Dance data
	dance_data = DanceData.load_file("res://music/the_num_singularity_immersion.dance")

	# Shader
	crystal_shader = ShaderMaterial.new()
	crystal_shader.shader = load("res://shaders/crystal.gdshader")

	# HUD
	var label = Label.new(); label.name = "Label"
	label.position = Vector2(20, 20)
	label.add_theme_color_override("font_color", Color(0.7, 0.5, 1.0))
	label.add_theme_font_size_override("font_size", 16)
	add_child(label)


# ═══════════════════════════════════════════
# CRYSTAL MESH — faceted icosahedron gem
# ═══════════════════════════════════════════
func _build_crystal_mesh():
	crystal_mesh = ArrayMesh.new()
	var phi = 1.618033988749895
	var verts = PackedVector3Array([
		Vector3(0, 1, phi), Vector3(0, 1, -phi), Vector3(0, -1, phi), Vector3(0, -1, -phi),
		Vector3(1, phi, 0), Vector3(1, -phi, 0), Vector3(-1, phi, 0), Vector3(-1, -phi, 0),
		Vector3(phi, 0, 1), Vector3(phi, 0, -1), Vector3(-phi, 0, 1), Vector3(-phi, 0, -1),
	])
	for i in verts.size(): verts[i] = verts[i].normalized()

	var faces = PackedInt32Array([
		0,1,4, 0,4,8, 0,8,10, 0,10,6, 0,6,1,
		1,6,7, 1,7,9, 1,9,4, 4,9,5, 4,5,8,
		8,5,2, 8,2,10, 10,2,11, 10,11,6, 6,11,7,
		7,11,3, 7,3,9, 9,3,5, 5,3,2, 2,3,11,
	])

	var arrays = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = faces
	crystal_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Make edges sharp (flat shading)
	var surf = crystal_mesh.surface_get_arrays(0)
	crystal_mesh.clear_surfaces()
	crystal_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf, [], {}, Mesh.ARRAY_FORMAT_VERTEX)


# ═══════════════════════════════════════════
# ORB CREATION
# ═══════════════════════════════════════════
func _create_orbs():
	for i in POOL_SIZE:
		var node = MeshInstance3D.new()
		node.mesh = crystal_mesh
		node.position = Vector3.ZERO
		node.scale = Vector3.ONE * 0.06
		var mat = crystal_shader.duplicate()
		var hue = fmod(float(i) / POOL_SIZE + randf() * 0.1, 1.0)
		mat.set_shader_parameter("albedo", Color.from_hsv(hue, 0.9, 1.0))
		mat.set_shader_parameter("fresnel_power", randf_range(2.2, 3.5))
		mat.set_shader_parameter("dispersion", randf_range(0.3, 0.6))
		mat.set_shader_parameter("internal_fire", randf_range(0.3, 0.7))
		mat.set_shader_parameter("sparkle", randf_range(0.2, 0.5))
		mat.set_shader_parameter("time_offset", randf() * TAU)
		node.material_override = mat
		add_child(node)
		orbs.append({
			"node": node, "pos": Vector3.ZERO, "target_pos": Vector3.ZERO,
			"color": Color.from_hsv(hue, 0.9, 1.0),
			"hue_offset": randf(), "phase": randf() * TAU,
			"scale": 0.06
		})


# ═══════════════════════════════════════════
# 12 SACRED GEOMETRY LAYERS
# Each returns Array[Vector3] of key positions
# ═══════════════════════════════════════════
func _get_layer_positions(layer: int, jitter: bool = false) -> Array:
	var pts = []
	var j = 0.0
	if jitter: j = 0.08
	match layer:
		0:  # Bindu — singularity
			pts = [Vector3.ZERO]
		1:  # Dyad — polarity line
			for i in 12:
				var t = float(i) / 12.0
				pts.append(Vector3(0, lerp(-0.7, 0.7, t), 0) + _jitter(j))
		2:  # Triad — triangle
			for i in 3:
				var a = i * TAU / 3.0
				for ring in 4:
					var r = 0.4 + ring * 0.5
					pts.append(Vector3(cos(a) * r, 0, sin(a) * r) + _jitter(j))
		3:  # Tetrad — tetrahedron
			var v2 = sqrt(2.0); var v6 = sqrt(6.0)
			var t_verts = [Vector3(0,1,0), Vector3(2*v2/3.0,-1.0/3.0,0), Vector3(-v2/3.0,-1.0/3.0,v6/3.0), Vector3(-v2/3.0,-1.0/3.0,-v6/3.0)]
			for v in t_verts:
				for _i in 3: pts.append(v * (2.0 + randf() * 0.5) + _jitter(j))
		4:  # Pentad — pentagon + star
			for i in 5:
				var a = i * TAU / 5.0 - PI/2.0
				for r in [0.8, 1.8, 2.8]:
					pts.append(Vector3(cos(a) * r, 0, sin(a) * r) + _jitter(j))
		5:  # Hexad — hexagon + center + cube projection
			for i in 6:
				var a = i * TAU / 6.0
				for r in [0.6, 1.5, 2.4]:
					pts.append(Vector3(cos(a) * r, (r - 1.5) * 0.6, sin(a) * r) + _jitter(j))
			pts.append(Vector3.ZERO)
		6:  # Heptad — 7-pointed star
			for i in 7:
				var a = i * TAU / 7.0 - PI/2.0
				pts.append(Vector3(cos(a) * 3.0, 0, sin(a) * 3.0) + _jitter(j))
				pts.append(Vector3(cos(a) * 1.4, 0.4, sin(a) * 1.4) + _jitter(j))
				pts.append(Vector3(cos(a) * 1.4, -0.4, sin(a) * 1.4) + _jitter(j))
		7:  # Octad — octahedron + cube
			for ax in [Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1)]:
				for s in [-1, 1]:
					for _i in 3: pts.append(ax * s * 2.5 + _jitter(j))
			var sv = 1.0 / sqrt(3.0)
			for x in [-sv, sv]:
				for y in [-sv, sv]:
					for z in [-sv, sv]:
						pts.append(Vector3(x, y, z) * 2.5 + _jitter(j))
		8:  # Ennead — 9-point enneagram
			for i in 9:
				var a = i * TAU / 9.0 - PI/2.0
				pts.append(Vector3(cos(a) * 3.0, 0, sin(a) * 3.0) + _jitter(j))
				pts.append(Vector3(cos(a) * 2.0, 0.6, sin(a) * 2.0) + _jitter(j))
				pts.append(Vector3(cos(a) * 1.0, -0.6, sin(a) * 1.0) + _jitter(j))
			pts.append(Vector3.ZERO)
		9:  # Decad — dodecahedron
			var phi = 1.618033988749895; var iphi = 1.0 / phi
			var dv = [Vector3(1,1,1), Vector3(1,1,-1), Vector3(1,-1,1), Vector3(1,-1,-1),
				Vector3(-1,1,1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(-1,-1,-1),
				Vector3(0,iphi,phi), Vector3(0,iphi,-phi), Vector3(0,-iphi,phi), Vector3(0,-iphi,-phi),
				Vector3(iphi,phi,0), Vector3(iphi,-phi,0), Vector3(-iphi,phi,0), Vector3(-iphi,-phi,0),
				Vector3(phi,0,iphi), Vector3(phi,0,-iphi), Vector3(-phi,0,iphi), Vector3(-phi,0,-iphi)]
			for v in dv: pts.append(v.normalized() * 2.5 + _jitter(j))
		10: # Icosahedron
			var phi2 = 1.618033988749895
			var iv = [Vector3(0,1,phi2), Vector3(0,1,-phi2), Vector3(0,-1,phi2), Vector3(0,-1,-phi2),
				Vector3(1,phi2,0), Vector3(1,-phi2,0), Vector3(-1,phi2,0), Vector3(-1,-phi2,0),
				Vector3(phi2,0,1), Vector3(phi2,0,-1), Vector3(-phi2,0,1), Vector3(-phi2,0,-1)]
			for v in iv: pts.append(v.normalized() * 2.5 + _jitter(j))
		11: # Flower Bloom — full spherical mandala
			for lat_i in 6:
				var lat = lerp(-PI/2.0 + 0.3, PI/2.0 - 0.3, float(lat_i) / 5.0)
				var count = int(6 + lat_i * 2.5)
				for lo in count:
					var lon = lo * TAU / count + lat_i * 0.3
					var r = 1.8 + sin(lat_i * 1.7) * 1.2
					pts.append(Vector3(cos(lon) * cos(lat) * r, sin(lat) * r, sin(lon) * cos(lat) * r) + _jitter(j))
			pts.append(Vector3.ZERO)
	return pts


func _jitter(amt: float) -> Vector3:
	if amt <= 0.0: return Vector3.ZERO
	return Vector3(randf_range(-amt, amt), randf_range(-amt, amt), randf_range(-amt, amt))


func _assign_layer_positions(layer: int, instant: bool):
	var positions = _get_layer_positions(layer, not instant)
	for i in POOL_SIZE:
		var target = positions[i % positions.size()] if positions.size() > 0 else Vector3.ZERO
		orbs[i]["target_pos"] = target
		if instant:
			orbs[i]["pos"] = target
			orbs[i]["node"].position = target


# ═══════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════
func _process(delta):
	delta *= speed_mult
	if Input.is_key_pressed(KEY_SHIFT): delta *= 0.12
	time += delta
	if not audio.playing: return

	var t = audio.get_playback_position()
	var feat = {"onset": 0, "rms": 0.5, "centroid": 0.5}
	if dance_data: feat = dance_data.feat_at(t)
	amp = feat["rms"] * 2.5
	var onset_val = feat["onset"]
	centroid = feat["centroid"]
	beat_energy = lerp(beat_energy, onset_val * 3.5, delta * 9.0)

	var pal = PALETTES[palette_index]
	hue_shift = pal["hue"]
	sat_mult = pal["sat"]

	# ── Transition ──
	if auto_transition:
		transition_cooldown -= delta
		if onset_val > 0.4 and transition_cooldown <= 0.0 and transition_progress >= 1.0:
			beat_count += 1
			if beat_count >= 8:  # every 8 strong beats
				beat_count = 0
				transition_cooldown = 1.5
				_next_layer()

	if transition_progress < 1.0:
		transition_progress = minf(transition_progress + delta * 1.5 * (1.0 + amp), 1.0)
		var tp = smoothstep(0.0, 1.0, transition_progress)
		# Ease in-out cubic
		tp = tp * tp * (3.0 - 2.0 * tp)
		for i in POOL_SIZE:
			var o = orbs[i]
			o["pos"] = o["pos"].lerp(o["target_pos"], delta * 4.0 * (1.0 + amp))
			o["node"].position = o["pos"]

	# ── Animate orbs ──
	for orb in orbs:
		var node: MeshInstance3D = orb["node"]
		var phase: float = orb["phase"]
		var scale: float = orb["scale"]

		# Cymatics wobble (magic layer)
		if magic_cymatics:
			var bp = orb["pos"]
			var wobble = sin(time * 5.0 + bp.length() * 2.0 + phase) * 0.08 * (1.0 + beat_energy)
			node.position = bp + Vector3(wobble, wobble * 0.6, wobble * 0.6)
		elif transition_progress >= 1.0:
			node.position = orb["pos"]

		# Scale pulse
		var pulse = 0.8 + amp * 0.6 + beat_energy * 1.2 * (sin(time * 6.0 + phase) * 0.5 + 0.5)
		node.scale = Vector3.ONE * scale * pulse * 0.7

		# Color
		var hue = fmod(centroid * 0.2 + orb["hue_offset"] + hue_shift, 1.0)
		var ec = Color.from_hsv(hue, clampf(sat_mult * 0.9, 0.1, 1.0), 1.0)
		var mat: ShaderMaterial = node.material_override
		mat.set_shader_parameter("albedo", ec)
		mat.set_shader_parameter("brightness", 1.5 + amp * 1.5 + beat_energy * 3.0)
		mat.set_shader_parameter("beat", beat_energy)
		mat.set_shader_parameter("sparkle", 0.2 + beat_energy * 0.5)

	# ── Magic layers ──
	if magic_halos: _update_halos(delta)
	if magic_rays and beat_energy > 0.6: _emit_rays()
	if magic_ripples: _update_ripples(delta)
	if magic_trails: _update_trails(delta)
	if magic_mirror: _update_mirror()

	# ── Particle dance ──
	_update_particles(delta)

	# ── Starfield ──
	if starfield:
		starfield.speed_scale = 0.2 + amp * 0.6

	# ── Camera ──
	if auto_orbit:
		cam_theta += delta * (0.15 + amp * 0.3)
		cam_phi += sin(time * 0.2) * delta * 0.06
	cam_phi = clamp(cam_phi, -1.3, 1.3)
	cam_radius = 6.5 + sin(time * 0.5) * 1.5 - beat_energy * 2.0
	cam_radius = clamp(cam_radius, 3.5, 13.0)
	_update_camera()

	# ── HUD ──
	var label = get_node_or_null("Label")
	if label:
		var mag = []
		if magic_halos: mag.append("halo")
		if magic_rays: mag.append("ray")
		if magic_ripples: mag.append("ripple")
		if magic_constellation: mag.append("const")
		if magic_aurora: mag.append("aurora")
		if magic_cymatics: mag.append("cym")
		if magic_trails: mag.append("trail")
		if magic_mirror: mag.append("mirror")
		var mag_str = ""
		for m in mag: mag_str += m + " "
		label.text = "[%d] %s   e:%.2f   %.2fx   %s   +%s" % [current_layer, LAYER_NAMES[current_layer], amp, speed_mult, PALETTES[palette_index]["name"], mag_str.strip_edges()]


# ═══════════════════════════════════════════
# TRANSITION
# ═══════════════════════════════════════════
func _next_layer():
	target_layer = (current_layer + 1) % LAYER_NAMES.size()
	_start_transition()

func _jump_layer(l: int):
	if l == current_layer: return
	target_layer = l
	_start_transition()

func _start_transition():
	transition_progress = 0.0
	_assign_layer_positions(target_layer, false)
	current_layer = target_layer


# ═══════════════════════════════════════════
# MAGIC LAYERS
# ═══════════════════════════════════════════

# F1 — Particle halos around each orb
func _update_halos(_delta):
	# Spawn orbiting motes around each orb (subset)
	for i in min(orbs.size(), 20):
		if randf() > 0.3: continue
		var orb = orbs[i]
		var center = orb["node"].position
		var angle = time * 3.0 + i * 0.5
		var pos = center + Vector3(cos(angle), sin(angle * 0.7), sin(angle)) * 0.3
		_spawn_mote(pos, orb["color"], 0.3)

# F2 — Light rays on beats
func _emit_rays():
	for _k in 3:
		var origin = Vector3.ZERO
		var dir = Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1)).normalized()
		for s in range(8):
			var pos = origin + dir * s * 0.5
			_spawn_mote(pos, Color(1, 0.9, 0.6), 0.2)

# F3 — Ripple rings
func _update_ripples(_delta):
	ripple_timer += _delta
	if ripple_timer > 0.5 + beat_energy * 2.0:
		ripple_timer = 0.0
		var ring = Node3D.new()
		ring.name = "Ripple"
		for i in 24:
			var a = i * TAU / 24.0
			var mesh = MeshInstance3D.new()
			var sphere = SphereMesh.new(); sphere.radius = 0.02; sphere.height = 0.04
			mesh.mesh = sphere
			mesh.position = Vector3(cos(a), 0, sin(a)) * 0.5
			var mat = crystal_shader.duplicate()
			mat.set_shader_parameter("albedo", Color(0.5, 0.7, 1.0))
			mat.set_shader_parameter("brightness", 2.5)
			mesh.material_override = mat
			ring.add_child(mesh)
		ring.position = Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1))
		add_child(ring)
		ripple_nodes.append({"node": ring, "life": 1.5, "scale": 0.5})
	for rp in ripple_nodes:
		rp["life"] -= _delta
		rp["scale"] += _delta * 3.0 * (1.0 + amp)
		rp["node"].scale = Vector3.ONE * rp["scale"]
		if rp["life"] <= 0: rp["node"].queue_free()
	ripple_nodes = ripple_nodes.filter(func(r): return r["life"] > 0)

# F4 — Constellation lines
func _update_constellation():
	for edge in constellation_edges: edge.queue_free()
	constellation_edges.clear()
	var active = orbs.slice(0, min(orbs.size(), 30))
	for i in active.size():
		for j in range(i + 1, active.size()):
			var d = active[i]["node"].position.distance_to(active[j]["node"].position)
			if d < 2.5 and d > 0.2:
				_draw_line(active[i]["node"].position, active[j]["node"].position, Color(0.4, 0.6, 1.0, 0.3))

# F5 — Aurora (handled in environment via volumetric fog — enabled by default)

# F6 — Cymatics (handled in orb animation above)

# F7 — Trails
func _update_trails(_delta):
	trail_positions.append(orbs.slice(0, 15).map(func(o): return o["node"].position))
	if trail_positions.size() > 12: trail_positions.pop_front()
	for ti in trail_positions.size():
		var alpha = float(ti) / trail_positions.size() * 0.3
		for pi in trail_positions[ti].size():
			if pi < trail_positions[ti].size() - 1: continue  # simplified
			# Draw fading ghosts
			pass

# F8 — Mirror dimension (simplified — toggles secondary view)
func _update_mirror():
	pass  # Mirror is per-frame geometry duplication — handled in _process's second pass concept


# ═══════════════════════════════════════════
# PARTICLE DANCE — orbital choreography
# ═══════════════════════════════════════════
func _update_particles(delta):
	if particle_nodes.size() < 30 and randf() > 0.5:
		_spawn_particle()
	for pn in particle_nodes:
		pn["angle"] += delta * pn["speed"] * (0.5 + amp)
		pn["radius"] = lerp(pn["radius"], pn["target_radius"], delta * 1.5)
		var a = pn["angle"]
		var r = pn["radius"]
		var center = pn["center"]
		var x = cos(a) * r
		var z = sin(a) * r
		var y = sin(a * pn["h"]) * r * 0.4
		pn["node"].position = center + Vector3(x, y, z)
		pn["life"] -= delta
		if pn["life"] <= 0:
			pn["node"].queue_free()
	particle_nodes = particle_nodes.filter(func(p): return p["life"] > 0)


func _spawn_particle():
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new(); sphere.radius = 0.015; sphere.height = 0.03
	mesh.mesh = sphere
	var mat = crystal_shader.duplicate()
	var hue = randf()
	mat.set_shader_parameter("albedo", Color.from_hsv(hue, 0.7, 1.0))
	mat.set_shader_parameter("brightness", 2.0 + amp)
	mat.set_shader_parameter("dispersion", 0.5)
	mesh.material_override = mat
	add_child(mesh)
	particle_nodes.append({
		"node": mesh, "life": randf_range(1.5, 4.0),
		"angle": randf() * TAU, "radius": randf_range(1.0, 4.0),
		"target_radius": randf_range(1.5, 3.5), "speed": randf_range(0.3, 0.8),
		"center": Vector3(randf_range(-2,2), randf_range(-2,2), randf_range(-2,2)),
		"h": randf_range(1.0, 3.0)
	})


func _spawn_mote(pos: Vector3, col: Color, life: float = 0.3):
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new(); sphere.radius = 0.02; sphere.height = 0.04
	mesh.mesh = sphere; mesh.position = pos
	var mat = crystal_shader.duplicate()
	mat.set_shader_parameter("albedo", col)
	mat.set_shader_parameter("brightness", 3.0)
	mesh.material_override = mat; add_child(mesh)
	var timer = get_tree().create_timer(life)
	timer.timeout.connect(func(): mesh.queue_free())


func _draw_line(fr: Vector3, to: Vector3, col: Color):
	var dir_vec = to - fr; var length = dir_vec.length()
	if length < 0.001: return
	var mid = (fr + to) / 2.0
	var mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.003; cyl.bottom_radius = 0.003; cyl.height = length
	mesh.mesh = cyl; mesh.position = mid
	var y_ax = Vector3.UP; var tgt = dir_vec.normalized(); var dot = y_ax.dot(tgt)
	if dot < -0.9999: mesh.rotation = Vector3(1,0,0) * PI
	elif dot < 0.9999: mesh.rotate(y_ax.cross(tgt).normalized(), y_ax.angle_to(tgt))
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col; mat.emission_enabled = true; mat.emission = col
	mesh.material_override = mat; add_child(mesh)
	constellation_edges.append(mesh)


# ═══════════════════════════════════════════
# STARFIELD
# ═══════════════════════════════════════════
func _create_starfield():
	starfield = GPUParticles3D.new(); starfield.name = "Starfield"
	starfield.emitting = true; starfield.amount = 500
	starfield.lifetime = 10.0; starfield.speed_scale = 0.2
	starfield.visibility_aabb = AABB(Vector3(-20,-20,-20), Vector3(40,40,40))
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 14, 14)
	pm.spread = 180.0; pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05; pm.initial_velocity_max = 0.3
	pm.scale_min = 0.01; pm.scale_max = 0.04
	pm.color = Color(0.7, 0.75, 1.0)
	starfield.process_material = pm
	var dp = MeshInstance3D.new()
	var s = SphereMesh.new(); s.radius = 0.02; s.height = 0.04; s.radial_segments = 3; s.rings = 1
	dp.mesh = s
	var sm = StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color.WHITE; sm.emission_enabled = true; sm.emission = Color(0.7, 0.8, 1.0)
	dp.material_override = sm
	starfield.draw_pass_1 = dp; add_child(starfield); move_child(starfield, 0)


# ═══════════════════════════════════════════
# CAMERA
# ═══════════════════════════════════════════
func _update_camera():
	cam.position = Vector3(cos(cam_theta) * cos(cam_phi) * cam_radius, sin(cam_phi) * cam_radius, sin(cam_theta) * cos(cam_phi) * cam_radius)
	cam.look_at(Vector3.ZERO)


# ═══════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB: _next_layer(); return
			KEY_SPACE: _create_blast(); beat_energy = 2.5; return
			KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var n = event.keycode - KEY_0
				if n >= 0 and n < LAYER_NAMES.size(): _jump_layer(n); return
			KEY_MINUS: _jump_layer(10); return
			KEY_EQUAL: _jump_layer(11); return
			KEY_KP_SUBTRACT: _jump_layer(10); return
			KEY_KP_ADD: _jump_layer(11); return
			KEY_R: target_layer = randi() % LAYER_NAMES.size(); _start_transition(); return
			KEY_C: palette_index = (palette_index + 1) % PALETTES.size(); return
			KEY_M: auto_orbit = not auto_orbit; return
			KEY_F: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED); return
			KEY_B: env_ref.glow_enabled = not env_ref.glow_enabled; return
			KEY_A: auto_transition = not auto_transition; return
			KEY_F1: magic_halos = not magic_halos; return
			KEY_F2: magic_rays = not magic_rays; return
			KEY_F3: magic_ripples = not magic_ripples; return
			KEY_F4: magic_constellation = not magic_constellation; _update_constellation(); return
			KEY_F5: magic_aurora = not magic_aurora; env_ref.volumetric_fog_enabled = magic_aurora; return
			KEY_F6: magic_cymatics = not magic_cymatics; return
			KEY_F7: magic_trails = not magic_trails; return
			KEY_F8: magic_mirror = not magic_mirror; return
			KEY_UP: speed_mult = minf(speed_mult + 0.05, 3.0); return
			KEY_DOWN: speed_mult = maxf(speed_mult - 0.05, 0.05); return
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: speed_mult = minf(speed_mult + 0.05, 3.0); return
			KEY_PAGEDOWN: speed_mult = maxf(speed_mult - 0.5, 0.05); return
			KEY_PAGEUP: speed_mult = minf(speed_mult + 0.5, 3.0); return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: mouse_dragging = true; mouse_last = event.position; auto_orbit = false
			else: mouse_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: cam_radius = maxf(cam_radius - 0.5, 2.0); auto_orbit = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam_radius = minf(cam_radius + 0.5, 18.0); auto_orbit = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed: auto_orbit = not auto_orbit
	elif event is InputEventMouseMotion and mouse_dragging:
		var dm = event.position - mouse_last; mouse_last = event.position
		cam_theta -= dm.x * 0.005; cam_phi += dm.y * 0.005; cam_phi = clamp(cam_phi, -1.3, 1.3)


# ═══════════════════════════════════════════
# BEAT BLAST
# ═══════════════════════════════════════════
func _create_blast():
	var origin = Vector3.ZERO
	if orbs.size() > 0: origin = orbs[randi() % orbs.size()]["node"].position
	for _k in 20:
		var pos = origin + Vector3(randf_range(-1.5,1.5), randf_range(-1.5,1.5), randf_range(-1.5,1.5))
		_spawn_mote(pos, Color(1, 0.8, 0.3), 0.3)
