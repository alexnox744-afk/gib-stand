class_name Enemy
extends Node3D

signal hit_processed(result: Dictionary)
signal reset_done

# Zone -> PhysicalBone3D (позиция для спавна оторванных конечностей)
var zone_nodes: Dictionary = {}
# Zone -> Area3D hitbox (из сцены Zombie.tscn)
var hitbox_nodes: Dictionary = {}
# Zone -> MeshInstance3D debug overlay
var hitbox_debug_nodes: Dictionary = {}
# Detached limb rigid bodies (spawned on sever)
var detached_limbs: Array[RigidBody3D] = []
# Все Area3D-хитбоксы плоским списком (включает оба torso-хитбокса)
var all_hitboxes: Array[Area3D] = []
# Все дебаг-оверлеи плоским списком. Нужен отдельно от hitbox_debug_nodes,
# т.к. словарь ключуется по зоне, а таз и торс делят зону "torso" — в словаре
# выживает только один, и оверлей таза иначе не подсвечивался бы тогглом.
var all_hitbox_debug_nodes: Array[MeshInstance3D] = []

var health: HealthComponent
var is_ragdoll: bool = false
var _glb_root: Node3D
var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D
var _limb_hider: LimbHider
var _anim_player: AnimationPlayer
var _anim_idle: String = ""
var _anim_walk: String = ""
var _anim_attack: String = ""

const ZONE_TO_BONE := {
	"head":        "mixamorig_Head",
	"torso":       "mixamorig_Spine1",
	"upper_arm_L": "mixamorig_LeftArm",
	"lower_arm_L": "mixamorig_LeftForeArm",
	"upper_arm_R": "mixamorig_RightArm",
	"lower_arm_R": "mixamorig_RightForeArm",
	"thigh_L":     "mixamorig_LeftUpLeg",
	"shin_L":      "mixamorig_LeftLeg",
	"thigh_R":     "mixamorig_RightUpLeg",
	"shin_R":      "mixamorig_RightLeg",
}

const ZONE_COLORS := {
	"head": Color(0.9, 0.7, 0.5),
	"torso": Color(0.4, 0.5, 0.8),
	"upper_arm_L": Color(0.5, 0.7, 0.4),
	"upper_arm_R": Color(0.5, 0.7, 0.4),
	"lower_arm_L": Color(0.4, 0.65, 0.35),
	"lower_arm_R": Color(0.4, 0.65, 0.35),
	"thigh_L": Color(0.35, 0.45, 0.7),
	"thigh_R": Color(0.35, 0.45, 0.7),
	"shin_L": Color(0.3, 0.4, 0.65),
	"shin_R": Color(0.3, 0.4, 0.65),
}

# Кость сустава, на которой остаётся культя при отрыве зоны. Декаль среза
# цепляется СЮДА, а не к самой оторванной кости (та схлопнута в точку).
const STUMP_PARENT_ZONE := {
	"head": "torso",
	"upper_arm_L": "torso", "upper_arm_R": "torso",
	"lower_arm_L": "upper_arm_L", "lower_arm_R": "upper_arm_R",
	"thigh_L": "torso", "thigh_R": "torso",
	"shin_L": "thigh_L", "shin_R": "thigh_R",
}

func _ready() -> void:
	health = HealthComponent.new()
	add_child(health)
	health.zone_severed.connect(_on_zone_severed)
	health.died.connect(_on_died)
	_attach_model()
	_collect_hitboxes_from_model()

func _attach_model() -> void:
	var packed: PackedScene = load("res://scenes/Zombie.tscn") as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate()
	_glb_root = inst as Node3D
	if _glb_root == null:
		inst.queue_free()
		return
	add_child(_glb_root)
	_skeleton = _find_skeleton(_glb_root)
	_simulator = _find_simulator(_glb_root)
	_tune_ragdoll_weight()
	# Модификатор-пряталка конечностей: добавляем последним ребёнком скелета,
	# чтобы в стеке модификаторов он шёл ПОСЛЕ PhysicalBoneSimulator3D.
	if _skeleton != null:
		_limb_hider = LimbHider.new()
		_limb_hider.name = "LimbHider"
		_skeleton.add_child(_limb_hider)
	# Материал не трогаем — у зомби из Mixamo своя текстура (раньше бежевый
	# skin_mat нужен был для безтекстурного Male.obj).
	_anim_player = _find_animation_player(_glb_root)
	_resolve_animations()
	_play_idle()

func _collect_hitboxes_from_model() -> void:
	if _glb_root == null:
		return
	_scan_node_for_hitboxes(_glb_root)
	_attach_hitboxes_to_bones()

func _scan_node_for_hitboxes(node: Node) -> void:
	if node is Area3D and node.has_meta("zone"):
		var zone: String = str(node.get_meta("zone"))
		var area := node as Area3D
		area.collision_layer = 2
		area.collision_mask = 0
		hitbox_nodes[zone] = area
		all_hitboxes.append(area)
		if node.get_parent() is Node3D:
			zone_nodes[zone] = node.get_parent() as Node3D
		var dbg := _make_debug_overlay(area)
		if dbg != null:
			area.add_child(dbg)
			hitbox_debug_nodes[zone] = dbg
			all_hitbox_debug_nodes.append(dbg)
	for child in node.get_children():
		_scan_node_for_hitboxes(child)

func _make_debug_overlay(area: Area3D) -> MeshInstance3D:
	var cs: CollisionShape3D = null
	for child in area.get_children():
		if child is CollisionShape3D:
			cs = child as CollisionShape3D
			break
	if cs == null or cs.shape == null:
		return null
	var dbg := MeshInstance3D.new()
	var dbg_mat := StandardMaterial3D.new()
	dbg_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.35)
	dbg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dbg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dbg.material_override = dbg_mat
	dbg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dbg.visible = false
	var shape := cs.shape
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var m := CapsuleMesh.new()
		m.radius = cap.radius
		m.height = cap.height
		dbg.mesh = m
	elif shape is BoxShape3D:
		var box := shape as BoxShape3D
		var m := BoxMesh.new()
		m.size = box.size
		dbg.mesh = m
	elif shape is SphereShape3D:
		var sph := shape as SphereShape3D
		var m := SphereMesh.new()
		m.radius = sph.radius
		m.height = sph.radius * 2.0
		dbg.mesh = m
	else:
		return null
	dbg.transform = cs.transform
	return dbg

func _find_simulator(node: Node) -> PhysicalBoneSimulator3D:
	if node is PhysicalBoneSimulator3D:
		return node as PhysicalBoneSimulator3D
	for child in node.get_children():
		var found := _find_simulator(child)
		if found != null:
			return found
	return null

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

# Раскладываем клипы по ролям: walk/attack лежат в одноимённых библиотеках
# ("ZombieWalking/...", "ZombieAttack/..."), idle — глобальный (без префикса).
func _resolve_animations() -> void:
	_anim_idle = ""
	_anim_walk = ""
	_anim_attack = ""
	if _anim_player == null:
		return
	for a in _anim_player.get_animation_list():
		if a.contains("Walking"):
			_anim_walk = a
		elif a.contains("Attack"):
			_anim_attack = a
		else:
			_anim_idle = a
	# Mixamo-клипы едут вперёд (root motion на кости Hips). Фиксируем горизонталь
	# корня, чтобы зомби анимировался НА МЕСТЕ — перемещение сделает будущий ИИ.
	if _anim_walk != "":
		_strip_root_motion(_anim_walk)
		# ZombieWalking.glb экспортнут с иной ориентацией корня (rest Hips 0° vs
		# -90° у idle/attack) — тело валится на 90°. Доворачиваем Hips клипа.
		_reorient_root(_anim_walk, Quaternion(Vector3.RIGHT, -PI / 2.0))
	if _anim_attack != "":
		_strip_root_motion(_anim_attack)

# Зануляем горизонтальное смещение корневой кости в клипе: X/Z держим на
# значении первого кадра, вертикальный bob (Y) оставляем для живости.
func _strip_root_motion(clip: String) -> void:
	if _anim_player == null:
		return
	var anim := _anim_player.get_animation(clip)
	if anim == null:
		return
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(ti)).contains("Hips"):
			continue
		var key_count := anim.track_get_key_count(ti)
		if key_count == 0:
			continue
		var first: Vector3 = anim.track_get_key_value(ti, 0)
		for ki in key_count:
			var v: Vector3 = anim.track_get_key_value(ti, ki)
			anim.track_set_key_value(ti, ki, Vector3(first.x, v.y, first.z))

# Доворачиваем корневую кость (Hips) клипа на компенсирующий поворот — лечит
# рассинхрон ориентации скелета между по-разному экспортированными glb.
func _reorient_root(clip: String, comp: Quaternion) -> void:
	if _anim_player == null:
		return
	var anim := _anim_player.get_animation(clip)
	if anim == null:
		return
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		if not str(anim.track_get_path(ti)).contains("Hips"):
			continue
		for ki in anim.track_get_key_count(ti):
			var q: Quaternion = anim.track_get_key_value(ti, ki)
			anim.track_set_key_value(ti, ki, q * comp)

func _play_clip(clip: String, loop: bool) -> void:
	if _anim_player == null or clip == "" or not _anim_player.has_animation(clip):
		return
	var anim := _anim_player.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_anim_player.play(clip)

func _play_idle() -> void:
	_play_clip(_anim_idle, true)

# Публичные переключатели — пригодятся будущему ИИ.
func play_walk() -> void:
	if not is_ragdoll and not health.is_dead:
		_play_clip(_anim_walk, true)

func play_attack() -> void:
	if not is_ragdoll and not health.is_dead:
		_play_clip(_anim_attack, false)

func play_idle() -> void:
	if not is_ragdoll and not health.is_dead:
		_play_idle()

func _apply_material_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_material_recursive(child, mat)

func _collapse_bone(zone: String) -> void:
	if _skeleton == null or not ZONE_TO_BONE.has(zone):
		return
	var bone_name: String = str(ZONE_TO_BONE[zone])
	var bone_idx := _skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return
	# Не ноль: нулевой scale делает базис кости сингулярным, а PhysicalBone3D
	# и его дочерний Hitbox наследуют это → Jolt спамит "singular basis".
	# 0.001 визуально схлопывает конечность в точку, но базис остаётся валидным.
	_skeleton.set_bone_pose_scale(bone_idx, Vector3.ONE * 0.001)
	# Регистрируем кость в модификаторе — он будет держать её схлопнутой даже
	# когда симуляция регдола каждый кадр пытается вернуть scale в 1.
	if _limb_hider != null:
		_limb_hider.hide_bone(bone_idx)

func _restore_all_bones() -> void:
	if _skeleton == null:
		return
	if _limb_hider != null:
		_limb_hider.clear_hidden()
	for i in _skeleton.get_bone_count():
		_skeleton.reset_bone_pose(i)

# Перевешиваем каждый хитбокс на BoneAttachment3D, привязанный к его кости.
# BoneAttachment сам следует за позой кости — и в покое, и в регдоле, — поэтому
# хитбоксы едут за упавшим телом и не "размазываются" после респавна (мы больше
# не трогаем их global_transform вручную).
func _attach_hitboxes_to_bones() -> void:
	if _skeleton == null:
		return
	for area in all_hitboxes:
		_attach_hitbox_to_bone(area)

func _attach_hitbox_to_bone(area: Area3D) -> void:
	var pbone := area.get_parent()
	if pbone == null or not (pbone is PhysicalBone3D):
		return
	var bone_name: String = (pbone as PhysicalBone3D).bone_name
	var bone_idx := _skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.name = "HBAttach_" + bone_name
	_skeleton.add_child(ba)
	ba.bone_name = bone_name
	# Сразу ставим attachment в позу кости, чтобы reparent корректно сохранил
	# мировое положение хитбокса (баним разницу базисов кости и капсулы в local).
	ba.transform = _skeleton.get_bone_global_pose(bone_idx)
	area.reparent(ba, true)
	# zone_nodes теперь указывает на BoneAttachment — он следует за костью всегда,
	# поэтому .global_position даёт реальную позицию и в стойке, и в регдоле.
	zone_nodes[str(area.get_meta("zone"))] = ba

func apply_hit(zone: String, _shot_dir: Vector3, weapon: WeaponData) -> Dictionary:
	var result := health.apply_damage(zone, weapon.damage, weapon.sever_power)
	hit_processed.emit(result)
	return result

func apply_corpse_hit(zone: String, weapon: WeaponData) -> Dictionary:
	var result := health.apply_dead_hit(zone, weapon.damage, weapon.sever_power)
	return result

func apply_splash(hit_pos: Vector3, weapon: WeaponData) -> void:
	for zone in zone_nodes.keys():
		if zone in health.severed_zones:
			continue
		var zone_node: Node3D = zone_nodes.get(zone)
		if zone_node == null:
			continue
		var dist: float = zone_node.global_position.distance_to(hit_pos)
		if dist <= weapon.splash_radius:
			var falloff: float = 1.0 - (dist / weapon.splash_radius)
			# Мёртвому пул не трогаем — расчленяем через dead-hit. Отрыв
			# конечностей трупа идёт тем же путём zone_severed → спавн RigidBody.
			if health.is_dead:
				health.apply_dead_hit(zone, weapon.splash_damage * falloff, weapon.sever_power)
			else:
				health.apply_damage(zone, weapon.splash_damage * falloff, weapon.sever_power)

# Взрыв физически расшвыривает кости активного регдола: импульс по каждой
# физкости в радиусе, сила ∝ близости (+ небольшой подброс вверх).
func apply_ragdoll_explosion(blast_pos: Vector3, force: float, radius: float) -> void:
	if not is_ragdoll or _simulator == null:
		return
	for child in _simulator.get_children():
		if not (child is PhysicalBone3D):
			continue
		var pb := child as PhysicalBone3D
		var dist := pb.global_position.distance_to(blast_pos)
		if dist > radius:
			continue
		var falloff := 1.0 - dist / radius
		var dir := (pb.global_position - blast_pos).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.UP
		pb.apply_central_impulse((dir + Vector3.UP * 0.4) * force * falloff)

# Пуля толкает ближайшую к точке попадания физкость регдола — в самой точке
# удара, чтобы тело крутануло от выстрела. No-op, пока враг кинематичен (не труп).
func apply_ragdoll_impulse_at(world_pos: Vector3, dir: Vector3, force: float) -> void:
	if not is_ragdoll or _simulator == null:
		return
	var best: PhysicalBone3D = null
	var best_dist := INF
	for child in _simulator.get_children():
		if not (child is PhysicalBone3D):
			continue
		var pb := child as PhysicalBone3D
		var d := pb.global_position.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = pb
	if best != null:
		best.apply_impulse(dir.normalized() * force, world_pos - best.global_position)

func _on_zone_severed(zone: String) -> void:
	var node: Node3D = zone_nodes.get(zone)
	if node == null:
		return

	var to_hide := _get_dependent_zones(zone)
	to_hide.append(zone)
	for z in to_hide:
		var hb: Area3D = hitbox_nodes.get(z)
		if hb:
			hb.collision_layer = 0
		var dbg: MeshInstance3D = hitbox_debug_nodes.get(z)
		if dbg:
			dbg.visible = false
		_collapse_bone(z)

	var rb := _spawn_detached_limb(zone)
	get_parent().add_child(rb)
	rb.global_position = node.global_position
	detached_limbs.append(rb)

func _get_dependent_zones(zone: String) -> Array:
	var deps := {
		"upper_arm_L": ["lower_arm_L"],
		"upper_arm_R": ["lower_arm_R"],
		"thigh_L": ["shin_L"],
		"thigh_R": ["shin_R"],
	}
	return deps.get(zone, [])

# BoneAttachment3D кости сустава, на которой держится культя зоны (для декали
# среза, которая должна ехать за телом и в стойке, и в регдоле).
func get_stump_attachment(zone: String) -> Node3D:
	var parent_zone: String = str(STUMP_PARENT_ZONE.get(zone, "torso"))
	return zone_nodes.get(parent_zone) as Node3D

func _spawn_detached_limb(zone: String) -> DetachedLimb:
	var rb := DetachedLimb.new()
	rb.mass = 1.0
	rb.gravity_scale = 2.0

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = DetachedLimb.CAP_RADIUS
	cap.height = DetachedLimb.CAP_HEIGHT
	col.shape = cap
	rb.add_child(col)

	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = DetachedLimb.CAP_RADIUS
	cm.height = DetachedLimb.CAP_HEIGHT
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ZONE_COLORS.get(zone, Color.RED)
	mat.roughness = 0.9
	mi.material_override = mat
	rb.add_child(mi)

	# Хитбокс на слое 2 — теперь по лежащей конечности можно стрелять.
	rb.setup_hitbox()

	return rb

# Конечность перемолота в гибы — убираем её из списка и сцены.
func remove_detached_limb(limb: RigidBody3D) -> void:
	detached_limbs.erase(limb)
	if is_instance_valid(limb):
		limb.queue_free()

func impulse_limb(_zone: String, direction: Vector3, force: float) -> void:
	if detached_limbs.is_empty():
		return
	var rb: RigidBody3D = detached_limbs.back()
	rb.apply_central_impulse(direction * force + Vector3(randf_range(-1,1), randf_range(0.5,1.5), randf_range(-1,1)))
	rb.apply_torque_impulse(Vector3(randf_range(-4,4), randf_range(-4,4), randf_range(-4,4)))

func _on_died(overkill: bool) -> void:
	if overkill:
		visible = false
	else:
		is_ragdoll = true
		_do_ragdoll_fall()

func _do_ragdoll_fall() -> void:
	if _simulator == null:
		return
	# Глушим анимацию — иначе она и физика дерутся за позу скелета.
	if _anim_player != null:
		_anim_player.stop()
	_simulator.physical_bones_start_simulation()

# Утяжеляем кости регдола: в сцене масса не задана (дефолт 1 — «пушинка»).
# Больше масса + гравитация + демпфирование = труп падает весомо и не
# трясётся как тряпка.
func _tune_ragdoll_weight() -> void:
	if _simulator == null:
		return
	for child in _simulator.get_children():
		if not (child is PhysicalBone3D):
			continue
		var pb := child as PhysicalBone3D
		# Вес и инерция — тело ощущается тяжёлым, а не пушинкой.
		pb.mass = 5.0
		pb.gravity_scale = 1.0
		pb.linear_damp = 0.8
		# Высокий угловой демпфер = суставы не болтаются, тело не складывается резко.
		pb.angular_damp = 5.0
		# Корневую кость (Hips, без сустава) не трогаем — она база регдола.
		if pb.joint_type == PhysicalBone3D.JOINT_TYPE_NONE:
			continue
		# Create Physical Skeleton делает PIN-суставы (точечные, БЕЗ угловых
		# лимитов — оттого тело складывается). Меняем на CONE с лимитом размаха.
		# Позвоночник из 3 сегментов (Spine/Spine1/Spine2) + Neck превращает торс
		# в гармошку — их суставы зажимаем почти намертво, корпус держится жёстко;
		# конечностям оставляем нормальную подвижность.
		var bn: String = pb.bone_name
		var rigid: bool = bn.contains("Spine") or bn.contains("Neck")
		# Локти/колени (ForeArm, LowerLeg=Leg без UpLeg) — шарниры, вдоль оси НЕ
		# скручиваются; плечи/бёдра — немного можно; позвоночник зажат.
		var elbow_knee: bool = bn.contains("ForeArm") or (bn.contains("Leg") and not bn.contains("UpLeg"))
		var twist: float = 6.0 if rigid else (2.0 if elbow_knee else 12.0)
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		# На Jolt у конусного сустава работают ТОЛЬКО swing/twist span (bias/
		# relaxation/softness он игнорирует). Жёсткость — углами + angular_damp.
		pb.set("joint_constraints/swing_span", 6.0 if rigid else 38.0)
		pb.set("joint_constraints/twist_span", twist)

# Тело разорвано взрывом: гасим регдол и прячем модель, дальше показываем только гибсы.
func gib() -> void:
	if _simulator != null and is_ragdoll:
		_simulator.physical_bones_stop_simulation()
	is_ragdoll = false
	visible = false

func reset() -> void:
	if _simulator != null and is_ragdoll:
		_simulator.physical_bones_stop_simulation()

	for rb in detached_limbs:
		if is_instance_valid(rb):
			rb.queue_free()
	detached_limbs.clear()

	for zone in hitbox_nodes:
		hitbox_nodes[zone].collision_layer = 2
	_restore_all_bones()

	rotation = Vector3.ZERO
	position = Vector3.ZERO
	visible = true
	is_ragdoll = false

	# Новый враг снова «дышит» idle-анимацией.
	_play_idle()

	health.reset()
	reset_done.emit()

func get_all_hitbox_areas() -> Array[Area3D]:
	var result: Array[Area3D] = []
	for zone in hitbox_nodes:
		result.append(hitbox_nodes[zone])
	return result
