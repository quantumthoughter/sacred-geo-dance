extends Node3D

# ═══════════════════════════════════════════
# QUANTUM DANCE — Micronized Sand Particle Engine
# 5-band audio → hidden sacred geometry → quantum equations
# ═══════════════════════════════════════════

# ── Audio ──
var audio: AudioStreamPlayer
var band_data: BandData
var time: float = 0.0
var speed_mult: float = 1.0

# 5-band live values
var sub_val: float = 0.0
var bass_val: float = 0.0
var mid_val: float = 0.0
var high_val: float = 0.0
var air_val: float = 0.0
var onset_val: float = 0.0
var rms_val: float = 0.0
var centroid_val: float = 0.5
var beat_e: float = 0.0

# ── Camera ──
var cam: Camera3D
var cam_theta: float = 0.0
var cam_phi: float = 0.2
var cam_radius: float = 9.0
var mouse_dragging: bool = false
var mouse_last: Vector2
var auto_orbit: bool = true

# ── Particle systems ──
var sand_shader: ShaderMaterial
var p_sub: GPUParticles3D
var p_bass: GPUParticles3D
var p_mid: GPUParticles3D
var p_high: GPUParticles3D
var p_air: GPUParticles3D
var particle_systems: Array = []

# ── Attractor nodes ──
var attractors: Array = []  # {node, base_pos, phase, geometry_type}
var attractor_root: Node3D

# ── Equations ──
var equation_root: Node3D
var equations_visible: bool = false
var equation_timer: float = 0.0
var equation_nodes: Array = []

# ── Neural overlay ──
var neural_visible: bool = false
var neural_edges: Array = []
var neural_timer: float = 0.0

# ── Visuals ──
var env_ref: Environment
var starfield: GPUParticles3D
var palette_index: int = 0
const PALETTES = [
	{"name": "Quantum Gold",  "sub": Color(0.9,0.7,0.2), "bass": Color(1,0.5,0.15), "mid": Color(0.2,0.7,0.9), "high": Color(0.6,0.3,1), "air": Color(1,0.9,0.6)},
	{"name": "Deep Space",    "sub": Color(0.3,0.1,0.6), "bass": Color(0.5,0.2,0.8), "mid": Color(0.1,0.5,0.9), "high": Color(0.3,0.7,1), "air": Color(0.8,0.9,1)},
	{"name": "Emerald Fire",  "sub": Color(0.1,0.6,0.3), "bass": Color(0.2,0.8,0.2), "mid": Color(0.1,0.5,0.6), "high": Color(0.3,0.9,0.7), "air": Color(0.7,1,0.8)},
	{"name": "Crimson",       "sub": Color(0.6,0.1,0.1), "bass": Color(0.9,0.2,0.2), "mid": Color(0.8,0.3,0.5), "high": Color(1,0.4,0.7), "air": Color(1,0.7,0.8)},
	{"name": "Void White",    "sub": Color(0.6,0.6,0.7), "bass": Color(0.7,0.7,0.8), "mid": Color(0.8,0.8,0.9), "high": Color(0.9,0.9,1), "air": Color(1,1,1)},
	{"name": "Sunset",        "sub": Color(1,0.4,0.1), "bass": Color(1,0.6,0.3), "mid": Color(0.9,0.3,0.5), "high": Color(0.6,0.2,0.9), "air": Color(1,0.8,0.5)},
]


# ═══════════════════════════════════════════
# BandData — loads .quantum JSON
# ═══════════════════════════════════════════
class BandData extends RefCounted:
	var sub: PackedFloat64Array; var bass: PackedFloat64Array
	var mid: PackedFloat64Array; var high: PackedFloat64Array
	var air: PackedFloat64Array; var onset: PackedFloat64Array
	var rms: PackedFloat64Array; var centroid: PackedFloat64Array
	var num_frames: int; var fps: float

	static func load_file(path: String) -> BandData:
		var f = FileAccess.open(path, FileAccess.READ)
		if not f: return null
		var j = JSON.new(); j.parse(f.get_as_text())
		var d = j.get_data()
		var bd = BandData.new()
		bd.sub = _arr(d, "sub_bass"); bd.bass = _arr(d, "bass")
		bd.mid = _arr(d, "mid"); bd.high = _arr(d, "high")
		bd.air = _arr(d, "air"); bd.onset = _arr(d, "onset")
		bd.rms = _arr(d, "rms"); bd.centroid = _arr(d, "centroid")
		bd.num_frames = d.get("num_frames", 0); bd.fps = d.get("fps", 30)
		return bd

	static func _arr(d: Dictionary, key: String) -> PackedFloat64Array:
		return PackedFloat64Array(d.get(key, []))

	func frame_at(t: float) -> Dictionary:
		if num_frames <= 0: return {"sub":0,"bass":0,"mid":0,"high":0,"air":0,"onset":0,"rms":0.5,"centroid":0.5}
		var i = clampi(int(t * fps), 0, num_frames - 1)
		return {
			"sub": sub[i] if i < sub.size() else 0.0, "bass": bass[i] if i < bass.size() else 0.0,
			"mid": mid[i] if i < mid.size() else 0.0, "high": high[i] if i < high.size() else 0.0,
			"air": air[i] if i < air.size() else 0.0, "onset": onset[i] if i < onset.size() else 0.0,
			"rms": rms[i] if i < rms.size() else 0.5, "centroid": centroid[i] if i < centroid.size() else 0.5
		}


# ═══════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════
func _ready():
	_setup_scene()
	_load_audio()
	audio.play()


func _setup_scene():
	# Audio
	audio = AudioStreamPlayer.new(); add_child(audio)

	# Environment
	var env = WorldEnvironment.new()
	env_ref = Environment.new()
	env_ref.background_color = Color(0.003, 0.002, 0.008)
	env_ref.ambient_light_color = Color(0.02, 0.01, 0.05)
	env_ref.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_ref.glow_enabled = true
	env_ref.glow_intensity = 4.0
	env_ref.glow_bloom = 0.9
	env_ref.glow_hdr_threshold = 0.3
	env_ref.glow_hdr_scale = 3.5
	env_ref.volumetric_fog_enabled = true
	env_ref.volumetric_fog_density = 0.004
	env_ref.volumetric_fog_albedo = Color(0.03, 0.01, 0.06)
	env_ref.volumetric_fog_emission = Color(0.06, 0.02, 0.1)
	env_ref.volumetric_fog_emission_energy = 0.5
	env.environment = env_ref; add_child(env)

	# Camera
	cam = Camera3D.new(); cam.current = true; cam.fov = 62; add_child(cam)
	_update_camera()

	# Starfield
	_create_starfield()

	# Sand shader
	sand_shader = ShaderMaterial.new()
	sand_shader.shader = load("res://shaders/sand.gdshader")

	# Attractor root
	attractor_root = Node3D.new(); attractor_root.name = "Attractors"
	add_child(attractor_root)

	# 5 particle systems
	p_sub  = _create_particle_system(1200, 0.04, 0.10, Vector3(0,0,0))
	p_bass = _create_particle_system(1000, 0.03, 0.08, Vector3(0,0,0))
	p_mid  = _create_particle_system(800, 0.025, 0.06, Vector3(0,0,0))
	p_high = _create_particle_system(600, 0.02, 0.05, Vector3(0,0,0))
	p_air  = _create_particle_system(400, 0.015, 0.04, Vector3(0,0,0))
	particle_systems = [p_sub, p_bass, p_mid, p_high, p_air]

	# Equation root
	equation_root = Node3D.new(); equation_root.name = "Equations"; add_child(equation_root)

	# Build sacred geometry attractors
	_build_attractors()

	# HUD
	var label = Label.new(); label.name = "Label"
	label.position = Vector2(20, 20)
	label.add_theme_color_override("font_color", Color(0.7, 0.6, 1.0))
	label.add_theme_font_size_override("font_size", 14)
	add_child(label)


func _load_audio():
	var fpath = "res://music/the num singularity immersion.mp3"
	var s = load(fpath)
	if s: audio.stream = s
	band_data = BandData.load_file("res://music/the_num_singularity_immersion.quantum")


# ═══════════════════════════════════════════
# PARTICLE SYSTEMS
# ═══════════════════════════════════════════
func _create_particle_system(amount: int, scale_min: float, scale_max: float, pos: Vector3) -> GPUParticles3D:
	var ps = GPUParticles3D.new()
	ps.emitting = true; ps.amount = amount
	ps.lifetime = 5.0; ps.speed_scale = 0.5
	ps.visibility_aabb = AABB(Vector3(-15,-15,-15), Vector3(30,30,30))
	ps.position = pos

	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 5.0
	pm.spread = 60.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.5; pm.initial_velocity_max = 1.5
	pm.scale_min = scale_min; pm.scale_max = scale_max
	pm.damping_min = 0.3; pm.damping_max = 0.7
	pm.radial_accel_min = -1.5; pm.radial_accel_max = 0.5
	pm.tangential_accel_min = -1.0; pm.tangential_accel_max = 1.0
	ps.process_material = pm

	var dp = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.04; sphere.height = 0.08
	sphere.radial_segments = 3; sphere.rings = 1
	dp.mesh = sphere
	var mat = sand_shader.duplicate()
	mat.set_shader_parameter("albedo", Color(0.8, 0.5, 0.2))
	mat.set_shader_parameter("energy", 2.0)
	mat.set_shader_parameter("grain_size", 1.2)
	dp.material_override = mat
	ps.draw_pass_1 = dp
	add_child(ps)
	return ps


# ═══════════════════════════════════════════
# SACRED GEOMETRY ATTRACTORS
# ═══════════════════════════════════════════
func _build_attractors():
	# Dodecahedron orbit (bass) — 20 vertices
	var phi = 1.618033988749895; var iphi = 1.0 / phi
	var dv = [Vector3(1,1,1), Vector3(1,1,-1), Vector3(1,-1,1), Vector3(1,-1,-1),
		Vector3(-1,1,1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(-1,-1,-1),
		Vector3(0,iphi,phi), Vector3(0,iphi,-phi), Vector3(0,-iphi,phi), Vector3(0,-iphi,-phi),
		Vector3(iphi,phi,0), Vector3(iphi,-phi,0), Vector3(-iphi,phi,0), Vector3(-iphi,-phi,0),
		Vector3(phi,0,iphi), Vector3(phi,0,-iphi), Vector3(-phi,0,iphi), Vector3(-phi,0,-iphi)]
	for v in dv:
		_add_attractor(v.normalized() * 4.0, "dodec")

	# Icosahedron (high) — 12 vertices, smaller scale
	var iv = [Vector3(0,1,phi), Vector3(0,1,-phi), Vector3(0,-1,phi), Vector3(0,-1,-phi),
		Vector3(1,phi,0), Vector3(1,-phi,0), Vector3(-1,phi,0), Vector3(-1,-phi,0),
		Vector3(phi,0,1), Vector3(phi,0,-1), Vector3(-phi,0,1), Vector3(-phi,0,-1)]
	for v in iv:
		_add_attractor(v.normalized() * 2.8, "ico")

	# Spiral ring (mid) — Fibonacci spiral in 3D
	var ga = PI * (3.0 - sqrt(5.0))
	for i in 14:
		var t = float(i) / 14; var theta = i * ga
		var r = 1.5 + t * 3.0; var h = (t - 0.5) * 3.0
		_add_attractor(Vector3(cos(theta)*r, h, sin(theta)*r), "spiral")

	# Torus ring (sub-bass) — large circle
	for i in 12:
		var a = i * TAU / 12.0
		_add_attractor(Vector3(cos(a)*5.0, 0, sin(a)*5.0), "torus")

	# Random scatter (air) — fast moving points
	for _i in 20:
		_add_attractor(Vector3(randf_range(-4,4), randf_range(-4,4), randf_range(-4,4)), "scatter")


func _add_attractor(pos: Vector3, gtype: String):
	var att = GPUParticlesAttractorSphere3D.new()
	att.position = pos
	att.strength = randf_range(2.0, 5.0)
	att.attenuation = 0.5
	att.radius = randf_range(0.5, 1.5)
	attractor_root.add_child(att)
	attractors.append({"node": att, "base_pos": pos, "phase": randf()*TAU, "type": gtype})


# ═══════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════
func _process(delta):
	delta *= speed_mult
	if Input.is_key_pressed(KEY_SHIFT): delta *= 0.1
	time += delta

	var t = 0.0
	var f = {"sub":0,"bass":0,"mid":0,"high":0,"air":0,"onset":0,"rms":0.5,"centroid":0.5}
	if audio.playing:
		t = audio.get_playback_position()
		if band_data: f = band_data.frame_at(t)
	else:
		# Demo mode — animate with time only
		f["sub"] = sin(time * 0.5) * 0.5 + 0.5
		f["bass"] = sin(time * 0.7 + 1.0) * 0.5 + 0.5
		f["mid"] = sin(time * 1.1 + 2.0) * 0.5 + 0.5
		f["high"] = sin(time * 1.3 + 3.0) * 0.5 + 0.5
		f["air"] = sin(time * 1.7 + 4.0) * 0.5 + 0.5
		f["onset"] = 0.0
		f["rms"] = sin(time * 0.3) * 0.3 + 0.4

	sub_val = f["sub"]; bass_val = f["bass"]; mid_val = f["mid"]
	high_val = f["high"]; air_val = f["air"]; onset_val = f["onset"]
	rms_val = f["rms"]; centroid_val = f["centroid"]
	beat_e = lerp(beat_e, onset_val * 3.0, delta * 8.0)

	var pal = PALETTES[palette_index]

	# ── Update particle system speeds ──
	p_sub.speed_scale = 0.3 + sub_val * 1.5
	p_bass.speed_scale = 0.4 + bass_val * 1.8
	p_mid.speed_scale = 0.5 + mid_val * 2.0
	p_high.speed_scale = 0.6 + high_val * 2.2
	p_air.speed_scale = 0.7 + air_val * 2.5

	# Update sand shader energy
	for i in particle_systems.size():
		var ps: GPUParticles3D = particle_systems[i]
		var vals = [sub_val, bass_val, mid_val, high_val, air_val]
		var colors = [pal["sub"], pal["bass"], pal["mid"], pal["high"], pal["air"]]
		var dp = ps.draw_pass_1
		if not dp: continue
		var mat: ShaderMaterial = dp.material_override
		mat.set_shader_parameter("albedo", colors[i])
		mat.set_shader_parameter("energy", 0.7 + vals[i] * 1.5)

	# ── Update attractors — musical orbit ──
	for att in attractors:
		var node: GPUParticlesAttractor3D = att["node"]
		var bp: Vector3 = att["base_pos"]
		var ph: float = att["phase"]
		var gtype: String = att["type"]

		match gtype:
			"dodec":
				node.position = bp.rotated(Vector3(0,1,0), time * 0.15 * (0.5 + bass_val))
				node.strength = 2.0 + bass_val * 6.0
			"ico":
				node.position = bp.rotated(Vector3(1,0,1).normalized(), time * 0.25 * (0.5 + high_val))
				node.strength = 1.5 + high_val * 5.0
			"spiral":
				node.position = bp + Vector3(sin(time*2+ph)*0.3, cos(time*1.7+ph)*0.3, cos(time*2.2+ph)*0.3) * (0.5+mid_val)
				node.strength = 1.0 + mid_val * 4.0
			"torus":
				node.position = bp.rotated(Vector3(0.3,1,0.2).normalized(), time * 0.1 * (0.5+sub_val))
				node.strength = 3.0 + sub_val * 6.0
			"scatter":
				node.position = bp + Vector3(sin(time*3+ph)*1.5, cos(time*2.5+ph)*1.5, sin(time*2.8+ph)*1.5) * (0.5+air_val)
				node.strength = 0.5 + air_val * 3.0

	# ── Beat burst — attractor surge ──
	if onset_val > 0.4 and beat_e > 0.8:
		for att in attractors:
			att["node"].strength += 8.0
		env_ref.glow_intensity = lerp(env_ref.glow_intensity, 7.0, delta * 10.0)
		env_ref.volumetric_fog_emission_energy = lerp(env_ref.volumetric_fog_emission_energy, 2.0, delta * 10.0)
	else:
		env_ref.glow_intensity = lerp(env_ref.glow_intensity, 4.0, delta * 4.0)
		env_ref.volumetric_fog_emission_energy = lerp(env_ref.volumetric_fog_emission_energy, 0.5, delta * 4.0)

	# ── Equations ──
	if equations_visible: _update_equations(delta)

	# ── Neural overlay ──
	if neural_visible: _update_neural(delta)

	# ── Starfield ──
	if starfield: starfield.speed_scale = 0.1 + rms_val * 0.8

	# ── Camera ──
	if auto_orbit:
		cam_theta += delta * (0.12 + rms_val * 0.3)
		cam_phi += sin(time * 0.2) * delta * 0.05
	cam_phi = clamp(cam_phi, -1.2, 1.2)
	cam_radius = 8.0 + sin(time * 0.4) * 2.0 - beat_e * 2.5
	cam_radius = clamp(cam_radius, 4.0, 16.0)
	_update_camera()

	# ── HUD ──
	var label = get_node_or_null("Label")
	if label:
		var extras = ""
		if equations_visible: extras += " [eq]"
		if neural_visible: extras += " [neural]"
		label.text = "S:%.2f B:%.2f M:%.2f H:%.2f A:%.2f  %.1fx  %s%s" % [sub_val, bass_val, mid_val, high_val, air_val, speed_mult, PALETTES[palette_index]["name"], extras]


# ═══════════════════════════════════════════
# QUANTUM EQUATIONS
# ═══════════════════════════════════════════
const EQUATIONS = [
	"|ψ⟩ = α|0⟩ + β|1⟩", "Δx·Δp ≥ ℏ/2", "E = ℏω",
	"iℏ ∂ψ/∂t = Ĥψ", "S = k log W", "F = -∇V",
	"∇·E = ρ/ε₀", "ds² = g_μν dx^μ dx^ν",
	"ψ(x,t) = Ae^{i(kx-ωt)}", "⟨ψ|Ĥ|ψ⟩",
	"e^{iπ} + 1 = 0", "∫ D[x] e^{iS/ℏ}",
	"∂_μ F^{μν} = μ₀ J^ν", "S = ∫ d⁴x √(-g) R",
	"|Φ⁺⟩ = (|00⟩+|11⟩)/√2", "𝒩 = 4 SYM",
	"Δ = b² - 4ac", "φ⁴ theory",
	"Z = Tr(e^{-βĤ})", "p + ½ρv² + ρgh = const",
	"∇ × B = μ₀J + μ₀ε₀ ∂E/∂t", "G_μν + Λg_μν = 8πG T_μν",
	"∮ B·dl = μ₀I_enc", "δS = 0",
]

func _update_equations(delta):
	equation_timer -= delta
	if equation_timer <= 0:
		equation_timer = randf_range(1.5, 4.0)
		_spawn_equation()
	# Fade out old equations
	for eq in equation_nodes:
		eq["life"] -= delta
		eq["node"].position += eq["vel"] * delta
		eq["node"].modulate.a = clampf(eq["life"] / eq["max_life"], 0.0, 0.7)
		eq["node"].scale = Vector3.ONE * (0.5 + eq["life"] / eq["max_life"] * 0.5)
		if eq["life"] <= 0: eq["node"].queue_free()
	var alive = []
	for e in equation_nodes:
		if e["life"] > 0: alive.append(e)
	equation_nodes = alive


func _spawn_equation():
	var eq = Label3D.new()
	eq.text = EQUATIONS[randi() % EQUATIONS.size()]
	eq.position = Vector3(randf_range(-3,3), randf_range(-2,2), randf_range(-3,3))
	eq.modulate = Color(0.6, 0.7, 1.0, 0.7)
	eq.font_size = 18
	eq.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	equation_root.add_child(eq)
	equation_nodes.append({
		"node": eq, "life": randf_range(2.0, 5.0), "max_life": randf_range(2.0, 5.0),
		"vel": Vector3(randf_range(-0.3,0.3), randf_range(0.1,0.5), randf_range(-0.3,0.3))
	})


# ═══════════════════════════════════════════
# NEURAL OVERLAY — synaptic connections
# ═══════════════════════════════════════════
func _update_neural(delta):
	neural_timer -= delta
	if neural_timer <= 0:
		neural_timer = 0.15
		# Clear old lines
		for edge in neural_edges: edge.queue_free()
		neural_edges.clear()
		# Sample attractor positions and draw connections
		var pts = []
		for att in attractors:
			var pos: Vector3 = att["node"].position
			if randf() > 0.4: continue
			pts.append(pos)
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				if pts[i].distance_to(pts[j]) < 4.5:
					_draw_neural_line(pts[i], pts[j])


func _draw_neural_line(fr: Vector3, to: Vector3):
	var dir_vec = to - fr; var length = dir_vec.length()
	if length < 0.01: return
	var mid = (fr + to) / 2.0
	var mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.002; cyl.bottom_radius = 0.002; cyl.height = length
	mesh.mesh = cyl; mesh.position = mid
	var y_ax = Vector3.UP; var tgt = dir_vec.normalized(); var dot = y_ax.dot(tgt)
	if dot < -0.9999: mesh.rotation = Vector3(1,0,0) * PI
	elif dot < 0.9999: mesh.rotate(y_ax.cross(tgt).normalized(), y_ax.angle_to(tgt))
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.6, 1.0, 0.2)
	mat.emission_enabled = true; mat.emission = Color(0.3, 0.5, 1.0)
	mesh.material_override = mat; add_child(mesh)
	neural_edges.append(mesh)


# ═══════════════════════════════════════════
# STARFIELD
# ═══════════════════════════════════════════
func _create_starfield():
	starfield = GPUParticles3D.new(); starfield.name = "Starfield"
	starfield.emitting = true; starfield.amount = 600
	starfield.lifetime = 10.0; starfield.speed_scale = 0.1
	starfield.visibility_aabb = AABB(Vector3(-20,-20,-20), Vector3(40,40,40))
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 14, 14)
	pm.spread = 180.0; pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.03; pm.initial_velocity_max = 0.15
	pm.scale_min = 0.008; pm.scale_max = 0.03
	pm.color = Color(0.6, 0.7, 1.0)
	starfield.process_material = pm
	var dp = MeshInstance3D.new()
	var s = SphereMesh.new(); s.radius = 0.015; s.height = 0.03; s.radial_segments = 3; s.rings = 1
	dp.mesh = s
	var sm = StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color.WHITE; sm.emission_enabled = true; sm.emission = Color(0.6, 0.7, 1.0)
	dp.material_override = sm
	starfield.draw_pass_1 = dp; add_child(starfield); move_child(starfield, 0)


# ═══════════════════════════════════════════
# CAMERA
# ═══════════════════════════════════════════
func _update_camera():
	cam.position = Vector3(cos(cam_theta)*cos(cam_phi)*cam_radius, sin(cam_phi)*cam_radius, sin(cam_theta)*cos(cam_phi)*cam_radius)
	cam.look_at(Vector3.ZERO)


# ═══════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE: beat_e = 3.0; _burst_equations(); return
			KEY_C: palette_index = (palette_index + 1) % PALETTES.size(); return
			KEY_Q: equations_visible = not equations_visible; return
			KEY_W: neural_visible = not neural_visible; return
			KEY_M: auto_orbit = not auto_orbit; return
			KEY_B: env_ref.glow_enabled = not env_ref.glow_enabled; return
			KEY_F: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED); return
			KEY_UP: speed_mult = minf(speed_mult + 0.05, 3.0); return
			KEY_DOWN: speed_mult = maxf(speed_mult - 0.05, 0.05); return
			KEY_EQUAL, KEY_PLUS: speed_mult = minf(speed_mult + 0.05, 3.0); return
			KEY_MINUS: speed_mult = maxf(speed_mult - 0.05, 0.05); return
			KEY_PAGEUP: speed_mult = minf(speed_mult + 0.5, 3.0); return
			KEY_PAGEDOWN: speed_mult = maxf(speed_mult - 0.5, 0.05); return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: mouse_dragging = true; mouse_last = event.position; auto_orbit = false
			else: mouse_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: cam_radius = maxf(cam_radius - 0.5, 2.0); auto_orbit = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam_radius = minf(cam_radius + 0.5, 18.0); auto_orbit = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed: auto_orbit = not auto_orbit
	elif event is InputEventMouseMotion and mouse_dragging:
		var dm = event.position - mouse_last; mouse_last = event.position
		cam_theta -= dm.x * 0.005; cam_phi += dm.y * 0.005; cam_phi = clamp(cam_phi, -1.2, 1.2)


func _burst_equations():
	for _k in 6: _spawn_equation()


# ═══════════════════════════════════════════
# DRAG-DROP AUDIO
# ═══════════════════════════════════════════
func _on_files_dropped(files: PackedStringArray):
	if files.size() > 0:
		_handle_dropped_file(files[0])


func _handle_dropped_file(path: String):
	# Run audio_bands.py on the dropped file
	var out = path.get_basename() + ".quantum"
	OS.execute("python3", ["res://scripts/audio_bands.py", path, out])
	# Reload
	var s = load(path)
	if s: audio.stream = s
	band_data = BandData.load_file(out)
	audio.play()
