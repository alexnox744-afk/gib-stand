extends Node3D

# Nodes (assigned in _ready via find_child / direct reference)
var enemy: Enemy
var orbit_camera: OrbitCamera
var gibs_pool: GibsPool
var decal_pool: DecalPool
var sound_log: SoundLog
var hit_info_panel: HitInfoPanel

# UI refs
var weapon_buttons: Array[Button] = []
var reset_button: Button
var hitbox_toggle: CheckButton
var shake_toggle: CheckButton
var decal_toggle: CheckButton
var gib_count_label: Label
var decal_count_label: Label

var active_weapon_idx: int = 0
var weapons: Array[WeaponData] = []
var show_hitboxes: bool = false
var enable_shake: bool = true
var enable_decals: bool = true

func _ready() -> void:
	_build_weapons()
	_build_scene()
	_build_ui()

# ─────────────────────────────────────────────────────────────
# WEAPONS
# ─────────────────────────────────────────────────────────────

func _build_weapons() -> void:
	weapons.clear()

	var fist := WeaponData.new()
	fist.weapon_name = "Fist"
	fist.hit_type = WeaponData.HitType.MELEE
	fist.damage = 8.0
	fist.dismember_force = 1.0
	fist.sever_power = 0.0
	fist.fire_sound = "whoosh_fist"
	fist.impact_sound = "punch_flesh"
	weapons.append(fist)

	var pistol := WeaponData.new()
	pistol.weapon_name = "Pistol"
	pistol.hit_type = WeaponData.HitType.HITSCAN_SINGLE
	pistol.damage = 18.0
	pistol.dismember_force = 3.0
	pistol.sever_power = 0.6
	pistol.fire_sound = "pistol_shot"
	pistol.impact_sound = "impact_flesh"
	weapons.append(pistol)

	var shotgun := WeaponData.new()
	shotgun.weapon_name = "Shotgun"
	shotgun.hit_type = WeaponData.HitType.HITSCAN_SPREAD
	shotgun.damage = 12.0
	shotgun.pellet_count = 8
	shotgun.spread_angle = 8.0
	shotgun.dismember_force = 7.0
	shotgun.sever_power = 2.5
	shotgun.fire_sound = "shotgun_blast"
	shotgun.impact_sound = "impact_flesh_wet"
	weapons.append(shotgun)

	var chaingun := WeaponData.new()
	chaingun.weapon_name = "Chaingun"
	chaingun.hit_type = WeaponData.HitType.HITSCAN_SINGLE
	chaingun.damage = 14.0
	chaingun.dismember_force = 4.0
	chaingun.sever_power = 0.9
	chaingun.fire_sound = "chaingun_fire"
	chaingun.impact_sound = "impact_flesh"
	weapons.append(chaingun)

	var rocket := WeaponData.new()
	rocket.weapon_name = "Rocket Launcher"
	rocket.hit_type = WeaponData.HitType.PROJECTILE_SPLASH
	rocket.damage = 80.0
	rocket.splash_radius = 2.0
	rocket.splash_damage = 60.0
	rocket.dismember_force = 15.0
	rocket.sever_power = 3.0
	rocket.gib_on_direct_hit = true
	rocket.fire_sound = "rocket_launch"
	rocket.impact_sound = "explosion_meat"
	weapons.append(rocket)

	var plasma := WeaponData.new()
	plasma.weapon_name = "Plasma"
	plasma.hit_type = WeaponData.HitType.HITSCAN_SINGLE
	plasma.damage = 30.0
	plasma.dismember_force = 5.0
	plasma.sever_power = 1.2
	plasma.fire_sound = "plasma_zap"
	plasma.impact_sound = "impact_energy"
	weapons.append(plasma)

# ─────────────────────────────────────────────────────────────
# SCENE BUILD
# ─────────────────────────────────────────────────────────────

func _build_scene() -> void:
	# Platform
	var platform_body := StaticBody3D.new()
	platform_body.name = "Platform"
	var platform_col := CollisionShape3D.new()
	var platform_box := BoxShape3D.new()
	platform_box.size = Vector3(10, 0.3, 10)
	platform_col.shape = platform_box
	platform_body.add_child(platform_col)
	var platform_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(10, 0.3, 10)
	platform_mesh.mesh = bm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.3, 0.3, 0.35)
	pmat.roughness = 0.95
	platform_mesh.material_override = pmat
	platform_body.add_child(platform_mesh)
	platform_body.position = Vector3(0, -0.15, 0)
	add_child(platform_body)

	# Light
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.4
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-3, 2, -2)
	fill.light_energy = 0.5
	fill.omni_range = 12.0
	add_child(fill)

	# World environment
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

	# Enemy pivot
	var pivot := Node3D.new()
	pivot.name = "EnemyPivot"
	pivot.position = Vector3(0, 0, 0)
	add_child(pivot)

	enemy = Enemy.new()
	enemy.name = "Enemy"
	pivot.add_child(enemy)

	# Orbit Camera
	orbit_camera = OrbitCamera.new()
	orbit_camera.name = "OrbitCamera"
	orbit_camera.target = pivot
	orbit_camera.distance = 4.0

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 75
	orbit_camera.add_child(cam)

	add_child(orbit_camera)

	# Pools
	gibs_pool = GibsPool.new()
	gibs_pool.name = "GibsPool"
	add_child(gibs_pool)

	decal_pool = DecalPool.new()
	decal_pool.name = "DecalPool"
	add_child(decal_pool)

	# Sound log
	sound_log = SoundLog.new()
	sound_log.name = "SoundLog"
	add_child(sound_log)

# ─────────────────────────────────────────────────────────────
# UI
# ─────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	var root_vb := VBoxContainer.new()
	root_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks reach the 3D viewport
	ui.add_child(root_vb)

	# Top bar: weapon selector
	var weapon_panel := PanelContainer.new()
	root_vb.add_child(weapon_panel)
	var weapon_hb := HBoxContainer.new()
	weapon_panel.add_child(weapon_hb)

	var wlabel := Label.new()
	wlabel.text = "Weapon: "
	weapon_hb.add_child(wlabel)

	weapon_buttons.clear()
	for i in weapons.size():
		var btn := Button.new()
		btn.text = weapons[i].weapon_name
		btn.toggle_mode = true
		btn.pressed.connect(_on_weapon_selected.bind(i, btn))
		weapon_hb.add_child(btn)
		weapon_buttons.append(btn)
	if not weapon_buttons.is_empty():
		weapon_buttons[0].set_pressed_no_signal(true)

	# Middle: spacer (covers the enemy — must pass clicks through)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(spacer)

	# Bottom row
	var bottom_hb := HBoxContainer.new()
	bottom_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(bottom_hb)

	# Hit info
	hit_info_panel = HitInfoPanel.new()
	hit_info_panel.custom_minimum_size = Vector2(230, 0)
	bottom_hb.add_child(hit_info_panel)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_hb.add_child(spacer2)

	# Debug controls
	var debug_panel := PanelContainer.new()
	bottom_hb.add_child(debug_panel)
	var debug_vb := VBoxContainer.new()
	debug_panel.add_child(debug_vb)

	reset_button = Button.new()
	reset_button.text = "RESET"
	reset_button.pressed.connect(_on_reset)
	debug_vb.add_child(reset_button)

	hitbox_toggle = CheckButton.new()
	hitbox_toggle.text = "Show Hitboxes"
	hitbox_toggle.toggled.connect(_on_hitbox_toggle)
	debug_vb.add_child(hitbox_toggle)

	shake_toggle = CheckButton.new()
	shake_toggle.text = "Camera Shake"
	shake_toggle.set_pressed_no_signal(true)
	shake_toggle.toggled.connect(func(v): enable_shake = v)
	debug_vb.add_child(shake_toggle)

	decal_toggle = CheckButton.new()
	decal_toggle.text = "Decals"
	decal_toggle.set_pressed_no_signal(true)
	decal_toggle.toggled.connect(func(v): enable_decals = v)
	debug_vb.add_child(decal_toggle)

	gib_count_label = Label.new()
	gib_count_label.text = "Gibs: 0"
	gib_count_label.add_theme_font_size_override("font_size", 12)
	debug_vb.add_child(gib_count_label)

	decal_count_label = Label.new()
	decal_count_label.text = "Decals: 0"
	decal_count_label.add_theme_font_size_override("font_size", 12)
	debug_vb.add_child(decal_count_label)

# ─────────────────────────────────────────────────────────────
# INPUT — SHOOT
# ─────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_do_shoot(event.position)

func _do_shoot(mouse_pos: Vector2) -> void:
	if enemy == null or enemy.health.is_dead:
		return

	var cam: Camera3D = _get_camera()
	if cam == null:
		return

	var weapon: WeaponData = weapons[active_weapon_idx]
	sound_log.play(weapon.fire_sound)

	match weapon.hit_type:
		WeaponData.HitType.HITSCAN_SINGLE, WeaponData.HitType.MELEE:
			_single_ray(mouse_pos, weapon)
		WeaponData.HitType.HITSCAN_SPREAD:
			_spread_rays(mouse_pos, weapon)
		WeaponData.HitType.PROJECTILE_SPLASH:
			_splash_shot(mouse_pos, weapon)

func _single_ray(mouse_pos: Vector2, weapon: WeaponData) -> void:
	var result := _raycast(mouse_pos)
	if result.is_empty():
		return
	_process_single_hit(result, weapon)

func _spread_rays(mouse_pos: Vector2, weapon: WeaponData) -> void:
	for i in weapon.pellet_count:
		var spread := Vector2(
			randf_range(-weapon.spread_angle, weapon.spread_angle),
			randf_range(-weapon.spread_angle, weapon.spread_angle)
		)
		var scattered_pos := mouse_pos + spread * 3.0
		var result := _raycast(scattered_pos)
		if result.is_empty():
			continue
		_process_single_hit(result, weapon)

func _splash_shot(mouse_pos: Vector2, weapon: WeaponData) -> void:
	var result := _raycast(mouse_pos)
	var hit_pos: Vector3
	var shot_dir: Vector3
	var cam := _get_camera()

	if result.is_empty():
		# Shoot to a point in front
		var ray_origin := cam.project_ray_origin(mouse_pos)
		var ray_dir := cam.project_ray_normal(mouse_pos)
		hit_pos = ray_origin + ray_dir * 5.0
		shot_dir = ray_dir
	else:
		hit_pos = result["position"]
		shot_dir = (result["position"] - cam.global_position).normalized()
		# Direct hit first — may already gib (rocket), then we're done
		_process_single_hit(result, weapon)
		if enemy.health.is_dead:
			return

	# Splash
	sound_log.play(weapon.impact_sound)
	enemy.apply_splash(hit_pos, weapon)

	# Check if should gib from splash overkill
	if enemy.health.is_dead:
		_trigger_gibs(hit_pos, shot_dir, weapon)
		return

	if enable_decals:
		decal_pool.spawn(hit_pos, Vector3.UP)

func _process_single_hit(raycast_result: Dictionary, weapon: WeaponData) -> void:
	var area: Area3D = raycast_result.get("collider")
	if area == null or not area.has_meta("zone"):
		return

	var zone: String = area.get_meta("zone")
	var hit_pos: Vector3 = raycast_result["position"]
	var hit_normal: Vector3 = raycast_result["normal"]
	var cam := _get_camera()
	var shot_dir := (hit_pos - cam.global_position).normalized()

	# Check instant gib
	if weapon.gib_on_direct_hit and not enemy.health.is_dead:
		# Force death + overkill
		enemy.health.current_hp = 0
		enemy.health.is_dead = true
		enemy.visible = false
		enemy.health.died.emit(true)
		sound_log.play(weapon.impact_sound)
		sound_log.play("gib_explosion")
		_trigger_gibs(hit_pos, shot_dir, weapon)
		hit_info_panel.update_hit({"zone": zone, "damage": weapon.damage, "zone_hp_before": 0,
			"zone_hp_after": 0, "total_hp_before": enemy.health.max_hp, "total_hp_after": 0,
			"severed": false, "died": true, "overkill": true})
		return

	var result := enemy.apply_hit(zone, shot_dir, weapon)
	sound_log.play(weapon.impact_sound)

	if result.get("severed", false):
		sound_log.play("sever_squelch")
		enemy.impulse_limb(zone, shot_dir, weapon.dismember_force)

	if result.get("overkill", false):
		sound_log.play("gib_explosion")
		_trigger_gibs(hit_pos, shot_dir, weapon)
	elif result.get("died", false):
		sound_log.play("zombie_death")
	else:
		if enable_decals:
			decal_pool.spawn(hit_pos, hit_normal)

	hit_info_panel.update_hit(result)

	if enable_shake and (result.get("overkill") or result.get("severed")):
		_camera_shake(0.15)

func _raycast(mouse_pos: Vector2) -> Dictionary:
	var cam := _get_camera()
	if cam == null:
		return {}
	var space := get_world_3d().direct_space_state
	var ray_origin := cam.project_ray_origin(mouse_pos)
	var ray_dir := cam.project_ray_normal(mouse_pos)
	var params := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	params.collision_mask = 2  # hitbox layer
	params.collide_with_areas = true   # hitboxes are Area3D
	params.collide_with_bodies = false # ignore platform/limbs
	return space.intersect_ray(params)

func _get_camera() -> Camera3D:
	if orbit_camera == null:
		return null
	for child in orbit_camera.get_children():
		if child is Camera3D:
			return child
	return null

func _trigger_gibs(pos: Vector3, direction: Vector3, weapon: WeaponData) -> void:
	gibs_pool.spawn_gibs(pos + Vector3(0, 0.8, 0), direction, weapon.dismember_force, 10)

func _camera_shake(strength: float) -> void:
	if orbit_camera == null:
		return
	var tween := create_tween()
	var orig := orbit_camera.global_position
	for i in 4:
		var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0).normalized() * strength
		tween.tween_property(orbit_camera, "global_position", orig + offset, 0.03)
		strength *= 0.6
	tween.tween_property(orbit_camera, "global_position", orig, 0.05)

# ─────────────────────────────────────────────────────────────
# UI CALLBACKS
# ─────────────────────────────────────────────────────────────

func _on_weapon_selected(idx: int, btn: Button) -> void:
	active_weapon_idx = idx
	for b in weapon_buttons:
		b.set_pressed_no_signal(false)
	btn.set_pressed_no_signal(true)

func _on_reset() -> void:
	enemy.reset()
	gibs_pool.clear_all()
	decal_pool.clear_all()
	hit_info_panel.update_hit({})
	# Re-apply hitbox debug state to the restored body
	_on_hitbox_toggle(show_hitboxes)

func _on_hitbox_toggle(enabled: bool) -> void:
	show_hitboxes = enabled
	for zone in enemy.hitbox_debug_nodes:
		enemy.hitbox_debug_nodes[zone].visible = enabled

# ─────────────────────────────────────────────────────────────
# PROCESS
# ─────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if gib_count_label:
		gib_count_label.text = "Gibs: %d" % gibs_pool.active_count()
	if decal_count_label:
		decal_count_label.text = "Decals: %d" % decal_pool.active_count()
