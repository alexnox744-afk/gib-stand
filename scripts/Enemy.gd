class_name Enemy
extends Node3D

signal hit_processed(result: Dictionary)
signal reset_done

# Zone -> PhysicalBone3D (позиция для спавна оторванных конечностей)
var zone_nodes: Dictionary = {}
# Zone -> Area3D hitbox (из сцены MaleBody.tscn)
var hitbox_nodes: Dictionary = {}
# Zone -> MeshInstance3D debug overlay
var hitbox_debug_nodes: Dictionary = {}
# Detached limb rigid bodies (spawned on sever)
var detached_limbs: Array[RigidBody3D] = []

var health: HealthComponent
var is_ragdoll: bool = false
var _glb_root: Node3D
var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D

const ZONE_TO_BONE := {
	"head":        "Neck",
	"upper_arm_L": "UpperArm.L",
	"lower_arm_L": "LowerArm.L",
	"upper_arm_R": "UpperArm.R",
	"lower_arm_R": "LowerArm.R",
	"thigh_L":     "UpperLeg.L",
	"shin_L":      "LowerLeg.L",
	"thigh_R":     "UpperLeg.R",
	"shin_R":      "LowerLeg.R",
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

func _ready() -> void:
	health = HealthComponent.new()
	add_child(health)
	health.zone_severed.connect(_on_zone_severed)
	health.died.connect(_on_died)
	_attach_model()
	_collect_hitboxes_from_model()

func _attach_model() -> void:
	var packed: PackedScene = load("res://scenes/MaleBody.tscn") as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate()
	_glb_root = inst as Node3D
	if _glb_root == null:
		inst.queue_free()
		return
	_glb_root.scale = Vector3.ONE * 0.83
	add_child(_glb_root)
	_skeleton = _find_skeleton(_glb_root)
	_simulator = _find_simulator(_glb_root)
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.78, 0.62, 0.51)
	skin_mat.roughness = 0.85
	_apply_material_recursive(_glb_root, skin_mat)

func _collect_hitboxes_from_model() -> void:
	if _glb_root == null:
		return
	_scan_node_for_hitboxes(_glb_root)

func _scan_node_for_hitboxes(node: Node) -> void:
	if node is Area3D and node.has_meta("zone"):
		var zone: String = str(node.get_meta("zone"))
		var area := node as Area3D
		area.collision_layer = 2
		area.collision_mask = 0
		hitbox_nodes[zone] = area
		if node.get_parent() is Node3D:
			zone_nodes[zone] = node.get_parent() as Node3D
		var dbg := _make_debug_overlay(area)
		if dbg != null:
			area.add_child(dbg)
			hitbox_debug_nodes[zone] = dbg
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
	_skeleton.set_bone_pose_scale(bone_idx, Vector3.ZERO)

func _restore_all_bones() -> void:
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		_skeleton.reset_bone_pose(i)

func apply_hit(zone: String, _shot_dir: Vector3, weapon: WeaponData) -> Dictionary:
	var result := health.apply_damage(zone, weapon.damage, weapon.sever_power)
	hit_processed.emit(result)
	return result

func apply_splash(hit_pos: Vector3, weapon: WeaponData) -> void:
	var all_zones: Array = HealthComponent.ZONE_HP.keys()
	for zone in all_zones:
		if zone in health.severed_zones:
			continue
		var zone_node: Node3D = zone_nodes.get(zone)
		if zone_node == null:
			continue
		var dist: float = zone_node.global_position.distance_to(hit_pos)
		if dist <= weapon.splash_radius:
			var falloff: float = 1.0 - (dist / weapon.splash_radius)
			health.apply_damage(zone, weapon.splash_damage * falloff, weapon.sever_power)

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

func _spawn_detached_limb(zone: String) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = 1.0
	rb.gravity_scale = 2.0

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.08
	cap.height = 0.3
	col.shape = cap
	rb.add_child(col)

	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.08
	cm.height = 0.3
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ZONE_COLORS.get(zone, Color.RED)
	mat.roughness = 0.9
	mi.material_override = mat
	rb.add_child(mi)

	return rb

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
	_simulator.physical_bones_start_simulation()

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

	health.reset()
	reset_done.emit()

func get_all_hitbox_areas() -> Array[Area3D]:
	var result: Array[Area3D] = []
	for zone in hitbox_nodes:
		result.append(hitbox_nodes[zone])
	return result
