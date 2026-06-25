extends Node3D

var enemy: Enemy
var orbit_camera: OrbitCamera
var gibs_pool: GibsPool
var decal_pool: DecalPool
var sound_log: SoundLog
var hit_info_panel: HitInfoPanel

var weapon_buttons: Array[Button] = []
var reset_button: Button
var hitbox_toggle: CheckButton
var shake_toggle: CheckButton
var decal_toggle: CheckButton
var auto_fire_toggle: CheckButton
var gib_count_label: Label
var decal_count_label: Label

var active_weapon_idx: int = 0
var weapons: Array[WeaponData] = []
var show_hitboxes: bool = false
var enable_shake: bool = true
var enable_decals: bool = true

var _auto_fire_enabled: bool = false
var _lmb_held: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _fire_timer: float = 0.0

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
	fist.fire_rate = 1.5
	fist.fire_sound = "whoosh_fist"
	fist.impact_sound = "punch_flesh"
	weapons.append(fist)

	var pistol := WeaponData.new()
	pistol.weapon_name = "Pistol"
	pistol.hit_type = WeaponData.HitType.HITSCAN_SINGLE
	pistol.damage = 18.0
	pistol.dismember_force = 3.0
	pistol.sever_power = 0.6
	pistol.fire_rate = 2.5
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
	shotgun.fire_rate = 1.0
	shotgun.fire_sound = "shotgun_blast"
	shotgun.impact_sound = "impact_flesh_wet"
	weapons.append(shotgun)

	var chaingun := WeaponData.new()
	chaingun.weapon_name = "Chaingun"
	chaingun.hit_type = WeaponData.HitType.HITSCAN_SINGLE
	chaingun.damage = 14.0
	chaingun.dismember_force = 4.0
	chaingun.sever_power = 0.9
	chaingun.fire_rate = 10.0
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
	rocket.fire_rate = 0.6
	rocket.fire_sound = "rocket_launch"
	rocket.impact_sound = "explosion_meat"
	weapons.append(rocket)

	var plasma := WeaponData.new()
	plasma.weapon_name = "Plasma"
	plasma.hit_type = WeaponData.HitType.HITSCAN_SINGLE
	plasma.damage = 30.0
	plasma.dismember_force = 5.0
	plasma.sever_power = 1.2
	plasma.fire_rate = 4.0
	plasma.fire_sound = "plasma_zap"
	plasma.impact_sound = "impact_energy"
	weapons.append(plasma)

# ─────────────────────────────────────────────────────────────
# SCENE BUILD
# ─────────────────────────────────────────────────────────────

func _build_scene() -> void:
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

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.4
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-3, 2, -2)
	fill.light_energy = 0.5
	fill.omni_range = 12.0
	add_child(fill)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

	var pivot := Node3D.new()
	pivot.name = "EnemyPivot"
	add_child(pivot)

	enemy = Enemy.new()
	enemy.name = "Enemy"
	pivot.add_child(enemy)

	orbit_camera = OrbitCamera.new()
	orbit_camera.name = "OrbitCamera"
	orbit_camera.target = pivot
	orbit_camera.distance = 4.0

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 75
	orbit_camera.add_child(cam)

	add_child(orbit_camera)

	gibs_pool = GibsPool.new()
	gibs_pool.name = "GibsPool"
	add_child(gibs_pool)

	decal_pool = DecalPool.new()
	decal_pool.name = "DecalPool"
	add_child(decal_pool)

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
	root_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_vb)

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

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(spacer)

	var bottom_hb := HBoxContainer.new()
	bottom_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(bottom_hb)

	hit_info_panel = HitInfoPanel.new()
	hit_info_panel.custom_minimum_size = Vector2(230, 0)
	bottom_hb.add_child(hit_info_panel)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_hb.add_child(spacer2)

	var debug_panel := PanelContainer.new()
	bottom_hb.add_child(debug_panel)
	var debug_vb := VBoxContainer.new()
	debug_panel.add_child(debug_vb)

	reset_button = Button.new()
	reset_button.text = "Spawn New  [R]"
	reset_button.pressed.connect(_on_reset)
	debug_vb.add_child(reset_button)

	hitbox_toggle = CheckButton.new()
	hitbox_toggle.text = "Show Hitboxes"
	hitbox_toggle.toggled.connect(_on_hitbox_toggle)
	debug_vb.add_child(hitbox_toggle)

	shake_toggle = CheckButton.new()
	shake_toggle.text = "Camera Shake"
	shake_toggle.set_pressed_no_signal(true)
	shake_toggle.toggled.connect(func(v: bool): enable_shake = v)
	debug_vb.add_child(shake_toggle)

	decal_toggle = CheckButton.new()
	decal_toggle.text = "Decals"
	decal_toggle.set_pressed_no_signal(true)
	decal_toggle.toggled.connect(func(v: bool): enable_decals = v)
	debug_vb.add_child(decal_toggle)

	auto_fire_toggle = CheckButton.new()
	auto_fire_toggle.text = "Auto Fire"
	auto_fire_toggle.toggled.connect(func(v: bool): _auto_fire_enabled = v)
	debug_vb.add_child(auto_fire_toggle)

	gib_count_label = Label.new()
	gib_count_label.text = "Gibs: 0"
	gib_count_label.add_theme_font_size_override("font_size", 12)
	debug_vb.add_child(gib_count_label)

	decal_count_label = Label.new()
	decal_count_label.text = "Decals: 0"
	decal_count_label.add_theme_font_size_override("font_size", 12)
	debug_vb.add_child(decal_count_label)

# ─────────────────────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_lmb_held = true
			_last_mouse_pos = event.position
			_do_shoot(event.position)
			_fire_timer = 1.0 / weapons[active_weapon_idx].fire_rate
		else:
			_lmb_held = false
	elif event is InputEventMouseMotion:
		_last_mouse_pos = event.position
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_on_reset()

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
		var ray_origin := cam.project_ray_origin(mouse_pos)
		var ray_dir := cam.project_ray_normal(mouse_pos)
		hit_pos = ray_origin + ray_dir * 5.0
		shot_dir = ray_dir
	else:
		hit_pos = result["position"]
		shot_dir = (result["position"] - cam.global_position).normalized()
		_process_single_hit(result, weapon)
		if enemy.health.is_dead:
			return

	sound_log.play(weapon.impact_sound)
	enemy.apply_splash(hit_pos, weapon)

	if enemy.health.is_dead:
		_trigger_gibs(hit_pos, shot_dir, weapon)
		_spawn_blood_burst(hit_pos + Vector3(0, 0.5, 0), shot_dir, 50)
		_spawn_blood_cloud(hit_pos + Vector3(0, 0.8, 0), 0.6)
		return

	_spawn_blood_burst(hit_pos + Vector3(0, 0.2, 0), Vector3.UP, 18)
	_spawn_blood_cloud(hit_pos + Vector3(0, 0.4, 0), 0.25)
	if enable_decals:
		for i in 3:
			decal_pool.spawn(
				hit_pos + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)),
				Vector3.UP)

func _process_single_hit(raycast_result: Dictionary, weapon: WeaponData) -> void:
	var area: Area3D = raycast_result.get("collider")
	if area == null or not area.has_meta("zone"):
		return

	var zone: String = area.get_meta("zone")
	var hit_pos: Vector3 = raycast_result["position"]
	var hit_normal: Vector3 = raycast_result["normal"]
	var cam := _get_camera()
	var shot_dir := (hit_pos - cam.global_position).normalized()

	if weapon.gib_on_direct_hit and not enemy.health.is_dead:
		enemy.health.current_hp = 0
		enemy.health.is_dead = true
		enemy.visible = false
		enemy.health.died.emit(true)
		sound_log.play(weapon.impact_sound)
		sound_log.play("gib_explosion")
		_trigger_gibs(hit_pos, shot_dir, weapon)
		_spawn_blood_burst(hit_pos + Vector3(0, 0.5, 0), shot_dir, 50)
		_spawn_blood_cloud(hit_pos + Vector3(0, 0.8, 0), 0.6)
		hit_info_panel.update_hit({"zone": zone, "damage": weapon.damage, "zone_hp_before": 0,
			"zone_hp_after": 0, "total_hp_before": enemy.health.max_hp, "total_hp_after": 0,
			"severed": false, "died": true, "overkill": true})
		return

	var result := enemy.apply_hit(zone, shot_dir, weapon)
	sound_log.play(weapon.impact_sound)

	if result.get("severed", false):
		sound_log.play("sever_squelch")
		enemy.impulse_limb(zone, shot_dir, weapon.dismember_force)
		_spawn_blood_burst(hit_pos, hit_normal, 22)
		_spawn_blood_cloud(hit_pos, 0.2)
		if enable_decals:
			for i in 3:
				decal_pool.spawn(
					hit_pos + Vector3(randf_range(-0.08, 0.08), randf_range(-0.08, 0.08), 0.0),
					hit_normal)

	if result.get("overkill", false):
		sound_log.play("gib_explosion")
		_trigger_gibs(hit_pos, shot_dir, weapon)
		_spawn_blood_burst(hit_pos + Vector3(0, 0.5, 0), shot_dir, 50)
		_spawn_blood_cloud(hit_pos + Vector3(0, 0.8, 0), 0.6)
	elif result.get("died", false):
		sound_log.play("zombie_death")
		_spawn_blood_burst(hit_pos + Vector3(0, 0.3, 0), shot_dir, 28)
		_spawn_blood_cloud(hit_pos + Vector3(0, 0.5, 0), 0.3)
		if enable_decals:
			decal_pool.spawn(hit_pos, hit_normal)
	else:
		_spawn_blood_burst(hit_pos, hit_normal, 10)
		if enable_decals:
			decal_pool.spawn(hit_pos, hit_normal)
			if randf() > 0.55:
				decal_pool.spawn(
					hit_pos + Vector3(randf_range(-0.12, 0.12), randf_range(-0.1, 0.1), 0.0),
					hit_normal)

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
	params.collision_mask = 2
	params.collide_with_areas = true
	params.collide_with_bodies = false
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
# BLOOD FX
# ─────────────────────────────────────────────────────────────

func _spawn_blood_burst(pos: Vector3, normal: Vector3, count: int) -> void:
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.7, 0.05, 0.05)
	drop_mat.roughness = 0.9
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.025
	drop_mesh.height = 0.05
	drop_mesh.material = drop_mat

	var p := CPUParticles3D.new()
	p.draw_pass_1 = drop_mesh
	p.one_shot = true
	p.explosiveness = 0.88
	p.amount = count
	p.lifetime = 0.6
	p.direction = normal
	p.spread = 60.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -8.0, 0)
	add_child(p)
	p.global_position = pos
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)

func _spawn_blood_cloud(pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.04, 0.04, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos

	var target_s := radius * 12.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(target_s, target_s, target_s), 0.4) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(0.55, 0.04, 0.04, 0.0), 0.4)
	get_tree().create_timer(0.5).timeout.connect(mi.queue_free)

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
	_on_hitbox_toggle(show_hitboxes)

func _on_hitbox_toggle(enabled: bool) -> void:
	show_hitboxes = enabled
	for zone in enemy.hitbox_debug_nodes:
		enemy.hitbox_debug_nodes[zone].visible = enabled

# ─────────────────────────────────────────────────────────────
# PROCESS
# ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if gib_count_label:
		gib_count_label.text = "Gibs: %d" % gibs_pool.active_count()
	if decal_count_label:
		decal_count_label.text = "Decals: %d" % decal_pool.active_count()

	if _auto_fire_enabled and _lmb_held:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_do_shoot(_last_mouse_pos)
			_fire_timer = 1.0 / weapons[active_weapon_idx].fire_rate
