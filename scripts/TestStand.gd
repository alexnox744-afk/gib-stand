extends Node3D

# Ниже этой доли урона (damage/MAX_HP) попадание не оставляет стойкую декаль —
# только брызги. Кулак (~0.08) не пачкает, пистолет (0.18) и выше — да.
const BLOOD_DECAL_MIN_RATIO := 0.1
# Сколько секунд труп-регдол продолжает натекать лужу после падения.
const CORPSE_POOL_TIME := 6.0

var enemy: Enemy
var orbit_camera: OrbitCamera
var gibs_pool: GibsPool
var decal_pool: DecalPool
var blood_pool: BloodPool
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
var _bleed_timer: float = 0.0   # тик порций крови из культей, пока враг истекает
var _bleed_elapsed: float = 0.0 # сколько уже длится кровотечение (для роста лужи)
var _pool_timer: float = 0.0    # тик пятен растущей лужи на полу
var _corpse_pool_elapsed: float = 0.0   # сколько труп уже натекает лужу

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
	rocket.fire_rate = 0.6
	rocket.fire_sound = "rocket_launch"
	rocket.impact_sound = "rocket_explode"
	rocket.explosion_color = Color(1.0, 0.6, 0.15, 0.9)   # оранжевый огненный
	rocket.explosion_scale = 7.0
	weapons.append(rocket)

	# Плазма — мини-ракетница: частые маленькие ЭНЕРГЕТИЧЕСКИЕ взрывы.
	var plasma := WeaponData.new()
	plasma.weapon_name = "Plasma"
	plasma.hit_type = WeaponData.HitType.PROJECTILE_SPLASH
	plasma.damage = 30.0
	plasma.splash_radius = 0.9                             # ~втрое меньше ракеты
	plasma.splash_damage = 30.0
	plasma.dismember_force = 6.0
	plasma.sever_power = 1.5
	plasma.fire_rate = 3.0                                 # быстрее ракеты, мельче взрыв
	plasma.fire_sound = "plasma_zap"
	plasma.impact_sound = "impact_energy"
	plasma.explosion_color = Color(0.35, 0.75, 1.0, 0.9)  # голубой энергетический
	plasma.explosion_scale = 3.2
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

	var enemy_scene := load("res://scenes/Enemy.tscn") as PackedScene
	enemy = enemy_scene.instantiate() as Enemy
	enemy.name = "Enemy"
	pivot.add_child(enemy)
	enemy.health.bled_out.connect(_on_enemy_bled_out)

	orbit_camera = OrbitCamera.new()
	orbit_camera.name = "OrbitCamera"
	orbit_camera.target = pivot
	orbit_camera.distance = 4.0
	orbit_camera.pitch = -20.0

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

	blood_pool = BloodPool.new()
	blood_pool.name = "BloodPool"
	blood_pool.decal_pool = decal_pool
	add_child(blood_pool)

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
	if enemy == null:
		return
	# Allow shooting dead ragdoll for blood, and lone detached limbs even after
	# the body itself is gone (e.g. gibbed by overkill).
	if enemy.health.is_dead and not enemy.is_ragdoll and enemy.detached_limbs.is_empty():
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
	var cam := _get_camera()
	if cam == null:
		return

	# Где детонирует ракета: первая поверхность по лучу — хитбокс врага ИЛИ пол/
	# тело рядом (маска 1|2), либо точка в воздухе при полном промахе.
	var result := _raycast_blast(mouse_pos)
	var blast_pos: Vector3
	if result.is_empty():
		blast_pos = cam.project_ray_origin(mouse_pos) + cam.project_ray_normal(mouse_pos) * 8.0
	else:
		blast_pos = result["position"]

	sound_log.play(weapon.impact_sound)
	_spawn_explosion_fx(blast_pos, weapon.explosion_color, weapon.explosion_scale)
	if enable_shake:
		_camera_shake(weapon.explosion_scale * 0.03)   # мельче взрыв → слабее тряска

	# Взрыв — единственный источник урона: радиальный фолофф в пределах splash_radius.
	var hp_before: float = enemy.health.current_hp
	var was_dead: bool = enemy.health.is_dead
	enemy.apply_splash(blast_pos, weapon)
	_splash_detached_limbs(blast_pos, weapon)   # взрыв разносит и лежащие части
	# Физически расшвыриваем регдол — труп реагирует на взрыв. Радиус волны шире
	# зоны урона, чтобы тело ощутимо подбрасывало даже от мелкого взрыва.
	enemy.apply_ragdoll_explosion(blast_pos, weapon.dismember_force * 12.0, weapon.splash_radius * 1.5)
	if was_dead:
		# Кровь от взрыва по трупу (урон и отрывы уже посчитаны в apply_splash).
		_spawn_blood_burst(blast_pos, Vector3.UP, _blood_count_for(weapon.splash_damage))
		_spawn_blood_cloud(blast_pos, _blood_cloud_radius_for(weapon.splash_damage))
		return

	var body_center := enemy.global_position + Vector3(0, 0.9, 0)
	var blast_dir := (body_center - blast_pos).normalized()

	var dealt := hp_before - enemy.health.current_hp
	if enemy.health.is_dead:
		sound_log.play("gib_explosion")
		enemy.gib()
		_trigger_gibs(enemy.global_position, blast_dir, weapon)
		_spawn_blood_burst(body_center, blast_dir, _blood_count_for(hp_before))
		_spawn_blood_cloud(body_center, _blood_cloud_radius_for(hp_before))
		hit_info_panel.update_hit({
			"zone": "blast", "damage": hp_before,
			"total_hp_before": hp_before, "total_hp_after": 0.0,
			"severed": false, "died": true, "overkill": true,
		})
	elif enemy.health.current_hp < hp_before:
		sound_log.play("explosion_meat")
		_spawn_blood_burst(blast_pos, Vector3.UP, _blood_count_for(dealt))
		_spawn_blood_cloud(blast_pos, _blood_cloud_radius_for(dealt))

func _process_single_hit(raycast_result: Dictionary, weapon: WeaponData) -> void:
	var area: Area3D = raycast_result.get("collider")
	if area == null:
		return
	# Попали по лежащей оторванной конечности — толкаем/перемалываем.
	if area.has_meta("detached_limb"):
		_hit_detached_limb(area, raycast_result, weapon)
		return
	if not area.has_meta("zone"):
		return

	var zone: String = area.get_meta("zone")
	var hit_pos: Vector3 = raycast_result["position"]
	var hit_normal: Vector3 = raycast_result["normal"]
	var cam := _get_camera()
	var shot_dir := (hit_pos - cam.global_position).normalized()

	var result := enemy.apply_hit(zone, shot_dir, weapon)

	# Dead ragdoll — try limb detachment, at least blood
	if result.is_empty():
		if enemy.is_ragdoll:
			# Пуля физически толкает труп в точке попадания.
			enemy.apply_ragdoll_impulse_at(hit_pos, shot_dir, weapon.dismember_force * 3.0)
			# BoneAttachment3D зоны: декаль на нём поедет за оседающим трупом.
			var bone_target: Node3D = enemy.zone_nodes.get(zone) as Node3D
			var cr := enemy.apply_corpse_hit(zone, weapon)
			if cr.get("severed", false):
				sound_log.play("sever_squelch")
				enemy.impulse_limb(zone, shot_dir, weapon.dismember_force)
				_spawn_blood_burst(hit_pos, shot_dir, 22)
				_spawn_blood_cloud(hit_pos, 0.2)
				if enable_decals:
					_spawn_stump_decal(zone)
					# Кость отрыва схлопнута в точку — декали оставляем в мире.
					for i in 3:
						decal_pool.spawn(
							hit_pos + Vector3(randf_range(-0.08, 0.08), randf_range(-0.08, 0.08), 0.0),
							hit_normal)
			else:
				_spawn_blood_burst(hit_pos, shot_dir, _blood_count_for(weapon.damage))
				_spawn_blood_cloud(hit_pos, _blood_cloud_radius_for(weapon.damage))
				if enable_decals and _blood_ratio(weapon.damage) >= BLOOD_DECAL_MIN_RATIO:
					decal_pool.spawn(hit_pos, hit_normal, bone_target, _blood_decal_size_for(weapon.damage), DecalPool.PRIO_HIGH)
		return

	sound_log.play(weapon.impact_sound)

	# BoneAttachment3D that tracks the hit zone's bone — decals parented here
	# follow the body as it ragdolls instead of staying frozen in world-space.
	var bone_target: Node3D = enemy.zone_nodes.get(zone) as Node3D

	# Кровь от удара — ЕДИНЫЙ источник: всплеск разрыва при отрыве, иначе формула
	# по доле урона. Смерть/оверкилл больше НЕ добавляют свою «спецкровь».
	if result.get("severed", false):
		sound_log.play("sever_squelch")
		enemy.impulse_limb(zone, shot_dir, weapon.dismember_force)
		_spawn_blood_burst(hit_pos, shot_dir, 22)
		_spawn_blood_cloud(hit_pos, 0.2)
		if enable_decals:
			_spawn_stump_decal(zone)
			for i in 3:
				# No bone_target: severed bone is already collapsed to scale 0.001,
				# a child decal would inherit that scale and become invisible.
				decal_pool.spawn(
					hit_pos + Vector3(randf_range(-0.08, 0.08), randf_range(-0.08, 0.08), 0.0),
					hit_normal)
	else:
		_spawn_blood_burst(hit_pos, shot_dir, _blood_count_for(result["damage"]))
		_spawn_blood_cloud(hit_pos, _blood_cloud_radius_for(result["damage"]))
		if enable_decals and _blood_ratio(result["damage"]) >= BLOOD_DECAL_MIN_RATIO:
			var dsize := _blood_decal_size_for(result["damage"])
			decal_pool.spawn(hit_pos, hit_normal, bone_target, dsize, DecalPool.PRIO_HIGH)
			if randf() > 0.55:
				decal_pool.spawn(
					hit_pos + Vector3(randf_range(-0.12, 0.12), randf_range(-0.1, 0.1), 0.0),
					hit_normal, bone_target, dsize * 0.7, DecalPool.PRIO_HIGH)

	# Событие смерти — только звук и гибы, без отдельной «спецкрови».
	if result.get("overkill", false):
		sound_log.play("gib_explosion")
		_trigger_gibs(hit_pos, shot_dir, weapon)
	elif result.get("died", false):
		sound_log.play("zombie_death")

	hit_info_panel.update_hit(result)

	# Убивающий удар толкает тело в регдол (no-op, пока враг ещё жив/кинематичен).
	enemy.apply_ragdoll_impulse_at(hit_pos, shot_dir, weapon.dismember_force * 3.0)

	if enable_shake and (result.get("overkill") or result.get("severed")):
		_camera_shake(0.15)

# Прямое попадание по оторванной конечности: толчок, а на исчерпании
# целостности — перемол в гибы.
func _hit_detached_limb(area: Area3D, raycast_result: Dictionary, weapon: WeaponData) -> void:
	var limb := area.get_parent() as DetachedLimb
	if limb == null:
		return
	var hit_pos: Vector3 = raycast_result["position"]
	var hit_normal: Vector3 = raycast_result["normal"]
	var cam := _get_camera()
	var shot_dir := (hit_pos - cam.global_position).normalized()

	sound_log.play(weapon.impact_sound)
	var pulverized := limb.take_hit(shot_dir, weapon.damage, weapon.dismember_force)
	if pulverized:
		sound_log.play("gib_explosion")
		gibs_pool.spawn_gibs(limb.global_position, shot_dir, weapon.dismember_force, 6)
		_spawn_blood_burst(hit_pos, shot_dir, 14)
		_spawn_blood_cloud(hit_pos, 0.2)
		enemy.remove_detached_limb(limb)
	else:
		_spawn_blood_burst(hit_pos, shot_dir, _blood_count_for(weapon.damage))
		_spawn_blood_cloud(hit_pos, _blood_cloud_radius_for(weapon.damage))

# Взрыв разносит и лежащие конечности в радиусе: толчок + возможный перемол.
func _splash_detached_limbs(blast_pos: Vector3, weapon: WeaponData) -> void:
	# Идём по копии — перемолотые удаляются из исходного списка.
	for limb in enemy.detached_limbs.duplicate():
		if not is_instance_valid(limb) or not (limb is DetachedLimb):
			continue
		var dl := limb as DetachedLimb
		var dist := dl.global_position.distance_to(blast_pos)
		if dist > weapon.splash_radius:
			continue
		var falloff := 1.0 - dist / weapon.splash_radius
		var dir := (dl.global_position - blast_pos).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.UP
		var pulverized := dl.take_hit(dir, weapon.splash_damage * falloff, weapon.dismember_force * falloff)
		if pulverized:
			gibs_pool.spawn_gibs(dl.global_position, dir, weapon.dismember_force, 6)
			_spawn_blood_burst(dl.global_position, Vector3.UP, 10)
			enemy.remove_detached_limb(dl)

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

# Луч для детонации взрыва: видит и хитбоксы врага (слой 2), и пол/тела (слой 1),
# поэтому ракета взрывается о ближайшую поверхность, а не улетает в пустоту.
func _raycast_blast(mouse_pos: Vector2) -> Dictionary:
	var cam := _get_camera()
	if cam == null:
		return {}
	var space := get_world_3d().direct_space_state
	var ray_origin := cam.project_ray_origin(mouse_pos)
	var ray_dir := cam.project_ray_normal(mouse_pos)
	var params := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	params.collision_mask = 1 | 2
	params.collide_with_areas = true
	params.collide_with_bodies = true
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

func _spawn_explosion_fx(pos: Vector3, color: Color = Color(1.0, 0.6, 0.15, 0.9), peak_scale: float = 7.0) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos

	var fade_color := color
	fade_color.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3.ONE * peak_scale, 0.25) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", fade_color, 0.25)
	get_tree().create_timer(0.3).timeout.connect(mi.queue_free)

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

# Доля нанесённого урона к полному запасу HP — общая база для объёма крови.
func _blood_ratio(damage: float) -> float:
	return clampf(damage / HealthComponent.MAX_HP, 0.0, 1.0)

# Капли всплеска: царапина → 3–4, тяжёлый выстрел (≈ весь пул) → ~30.
func _blood_count_for(damage: float) -> int:
	return roundi(lerpf(3.0, 30.0, _blood_ratio(damage)))

# Радиус облака крови по той же доле урона.
func _blood_cloud_radius_for(damage: float) -> float:
	return lerpf(0.05, 0.5, _blood_ratio(damage))

# Размер декали-пятна в точке попадания по той же доле урона.
func _blood_decal_size_for(damage: float) -> float:
	return lerpf(0.1, 0.45, _blood_ratio(damage))

func _spawn_blood_burst(pos: Vector3, dir: Vector3, count: int) -> void:
	# Пул капель сам считает баллистику и роняет пятна на пол. Бюджет декалей
	# тратится только если включены (пул сам спавнит через свой decal_pool).
	blood_pool.decal_pool = decal_pool if enable_decals else null
	blood_pool.spawn_burst(pos, dir, mini(count, 32))

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

# Продолжающееся кровотечение из культей, пока враг ещё жив и истекает. Частота
# порций растёт с общим bleed_rate, объём из каждой культи — с её вкладом в
# SEVER_BLEED (голова хлещет фонтаном, рука капает).
func _update_stump_bleeding(delta: float) -> void:
	if enemy == null:
		return
	var bleeding_alive := not enemy.health.is_dead and enemy.health.bleed_rate > 0.0
	var corpse := enemy.health.is_dead and enemy.is_ragdoll
	if not bleeding_alive and not corpse:
		_bleed_elapsed = 0.0
		_corpse_pool_elapsed = 0.0
		return

	# Фонтаны брызг из культей — только пока враг жив и активно истекает.
	if bleeding_alive:
		_bleed_elapsed += delta
		_corpse_pool_elapsed = 0.0
		_bleed_timer -= delta
		if _bleed_timer <= 0.0:
			_bleed_timer = clampf(6.0 / enemy.health.bleed_rate, 0.08, 0.35)
			var body_center := enemy.global_position + Vector3(0, 0.9, 0)
			for zone in enemy.health.severed_zones:
				var rate := float(HealthComponent.SEVER_BLEED.get(zone, 0.0))
				if rate <= 0.0:
					continue
				var stump: Node3D = enemy.zone_nodes.get(zone)
				if stump == null:
					continue
				var out := stump.global_position - body_center
				out.y = 0.0
				var dir := out.normalized() + Vector3.UP * 1.5
				_spawn_blood_burst(stump.global_position, dir, clampi(roundi(rate / 30.0), 1, 4))
	else:
		_corpse_pool_elapsed += delta

	# Лужа на полу: у живого под культями, у трупа ещё CORPSE_POOL_TIME секунд
	# под культями И центром тела (регдол истекает, пока кровь не «свернулась»).
	if not enable_decals:
		return
	if corpse and _corpse_pool_elapsed >= CORPSE_POOL_TIME:
		return
	_pool_timer -= delta
	if _pool_timer > 0.0:
		return
	_pool_timer = 0.35
	var grow := _bleed_elapsed if bleeding_alive else 3.0
	var pool_size := lerpf(0.15, 0.5, clampf(grow / 3.0, 0.0, 1.0))
	for zone in enemy.health.severed_zones:
		var stump: Node3D = enemy.zone_nodes.get(zone)
		if stump != null:
			var sp := stump.global_position
			decal_pool.spawn(Vector3(sp.x, 0.02, sp.z), Vector3.UP, null, pool_size)
	if corpse:
		var torso: Node3D = enemy.zone_nodes.get("torso")
		if torso != null:
			var tp := torso.global_position
			decal_pool.spawn(Vector3(tp.x, 0.02, tp.z), Vector3.UP, null, pool_size)

# Декаль на срезе культи: на месте отрыва, привязана к кости сустава (едет за
# телом). Нормаль смотрит наружу от центра тела, чтобы лечь на срез.
func _spawn_stump_decal(zone: String) -> void:
	var stump := enemy.get_stump_attachment(zone)
	var src: Node3D = enemy.zone_nodes.get(zone) as Node3D
	if stump == null or src == null:
		return
	var pos := src.global_position
	var nrm := pos - (enemy.global_position + Vector3(0, 0.9, 0))
	if nrm.length() < 0.001:
		nrm = Vector3.UP
	nrm = nrm.normalized()
	# Несколько крупных пятен с разбросом, чтобы срез был сочно залит и читался.
	for i in 3:
		var jitter := Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05))
		decal_pool.spawn(pos + jitter, nrm, stump, randf_range(0.35, 0.5), DecalPool.PRIO_HIGH)

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
	blood_pool.clear_all()
	hit_info_panel.update_hit({})
	_on_hitbox_toggle(show_hitboxes)

func _on_hitbox_toggle(enabled: bool) -> void:
	show_hitboxes = enabled
	# Идём по плоскому списку, а не по словарю зон: иначе оверлей таза (зона
	# "torso", затёртая торсом в словаре) никогда не подсвечивался бы.
	for dbg in enemy.all_hitbox_debug_nodes:
		dbg.visible = enabled

# Враг истёк кровью после отрыва (голова/рука) — даём звук и брызги в момент,
# когда тело наконец падает, чтобы отложенная смерть читалась как смерть.
func _on_enemy_bled_out() -> void:
	sound_log.play("zombie_death")
	# Вместо отдельного предсмертного всплеска — финальная лужа под телом
	# (дальше труп-регдол ещё досачивает её сам через _update_stump_bleeding).
	if enable_decals:
		var torso: Node3D = enemy.zone_nodes.get("torso")
		if torso != null:
			var tp := torso.global_position
			for i in 3:
				var off := Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
				decal_pool.spawn(Vector3(tp.x + off.x, 0.02, tp.z + off.z), Vector3.UP, null, randf_range(0.35, 0.5))

# ─────────────────────────────────────────────────────────────
# PROCESS
# ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_stump_bleeding(delta)
	if gib_count_label:
		gib_count_label.text = "Gibs: %d" % gibs_pool.active_count()
	if decal_count_label:
		decal_count_label.text = "Decals: %d" % decal_pool.active_count()

	if _auto_fire_enabled and _lmb_held:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_do_shoot(_last_mouse_pos)
			_fire_timer = 1.0 / weapons[active_weapon_idx].fire_rate
