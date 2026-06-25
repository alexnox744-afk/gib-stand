class_name Enemy
extends Node3D

signal hit_processed(result: Dictionary)
signal reset_done

# Zone -> Node3D (visual part)
var zone_nodes: Dictionary = {}
# Zone -> Area3D hitbox
var hitbox_nodes: Dictionary = {}
# Zone -> MeshInstance3D translucent hitbox overlay (debug draw)
var hitbox_debug_nodes: Dictionary = {}
# Detached limb rigid bodies (spawned on sever)
var detached_limbs: Array[RigidBody3D] = []

var health: HealthComponent
var is_ragdoll: bool = false
var _original_transforms: Dictionary = {}
var _ragdoll_tween: Tween
var _glb_root: Node3D
var _skeleton: Skeleton3D

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

# Кость-якорь для позиционирования хитбокса каждой зоны
const ZONE_ALIGN_BONE := {
	"torso":       "Torso",
	"head":        "Head",
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
	_build_body()

func _build_body() -> void:
	# Torso
	_add_zone("torso", _box_mesh(Vector3(0.38, 0.48, 0.22), ZONE_COLORS["torso"]),
		Vector3(0, 0.9, 0), _box_shape(Vector3(0.38, 0.48, 0.22)))

	# Head
	_add_zone("head", _sphere_mesh(0.16, ZONE_COLORS["head"]),
		Vector3(0, 1.44, 0), _sphere_shape(0.17))

	# Arms L
	_add_zone("upper_arm_L", _capsule_mesh(0.075, 0.28, ZONE_COLORS["upper_arm_L"]),
		Vector3(0.32, 1.0, 0), _capsule_shape(0.075, 0.28))
	_add_zone("lower_arm_L", _capsule_mesh(0.06, 0.26, ZONE_COLORS["lower_arm_L"]),
		Vector3(0.32, 0.66, 0), _capsule_shape(0.06, 0.26))

	# Arms R
	_add_zone("upper_arm_R", _capsule_mesh(0.075, 0.28, ZONE_COLORS["upper_arm_R"]),
		Vector3(-0.32, 1.0, 0), _capsule_shape(0.075, 0.28))
	_add_zone("lower_arm_R", _capsule_mesh(0.06, 0.26, ZONE_COLORS["lower_arm_R"]),
		Vector3(-0.32, 0.66, 0), _capsule_shape(0.06, 0.26))

	# Legs L
	_add_zone("thigh_L", _capsule_mesh(0.09, 0.36, ZONE_COLORS["thigh_L"]),
		Vector3(0.13, 0.48, 0), _capsule_shape(0.09, 0.36))
	_add_zone("shin_L", _capsule_mesh(0.075, 0.32, ZONE_COLORS["shin_L"]),
		Vector3(0.13, 0.11, 0), _capsule_shape(0.075, 0.32))

	# Legs R
	_add_zone("thigh_R", _capsule_mesh(0.09, 0.36, ZONE_COLORS["thigh_R"]),
		Vector3(-0.13, 0.48, 0), _capsule_shape(0.09, 0.36))
	_add_zone("shin_R", _capsule_mesh(0.075, 0.32, ZONE_COLORS["shin_R"]),
		Vector3(-0.13, 0.11, 0), _capsule_shape(0.075, 0.32))

	# Save original transforms
	for zone in zone_nodes:
		_original_transforms[zone] = zone_nodes[zone].transform

	_attach_model()

func _attach_model() -> void:
	var packed: PackedScene = load("res://models/male.glb") as PackedScene
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
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.78, 0.62, 0.51)
	skin_mat.roughness = 0.85
	_apply_material_recursive(_glb_root, skin_mat)
	_align_hitboxes_to_bones()

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

func _align_hitboxes_to_bones() -> void:
	if _skeleton == null:
		return
	for zone in ZONE_ALIGN_BONE:
		var bone_name: String = str(ZONE_ALIGN_BONE[zone])
		var bone_idx := _skeleton.find_bone(bone_name)
		if bone_idx < 0:
			continue
		# get_bone_global_pose возвращает позу в локальном пространстве Skeleton3D
		var bone_local_pos := _skeleton.get_bone_global_pose(bone_idx).origin
		var world_pos := _skeleton.to_global(bone_local_pos)
		var enemy_local_pos := to_local(world_pos)
		var zone_node: Node3D = zone_nodes.get(zone)
		if zone_node:
			zone_node.position = enemy_local_pos

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

func _add_zone(zone_name: String, mesh_inst: MeshInstance3D, pos: Vector3, col_shape: CollisionShape3D) -> void:
	var pivot := Node3D.new()
	pivot.name = zone_name
	pivot.position = pos
	add_child(pivot)
	mesh_inst.visible = false  # OBJ model is the visual; primitives are hitbox scaffolding only
	pivot.add_child(mesh_inst)

	var area := Area3D.new()
	area.name = zone_name + "_hitbox"
	area.set_meta("zone", zone_name)
	area.collision_layer = 2
	area.collision_mask = 0
	area.add_child(col_shape)
	pivot.add_child(area)

	# Translucent debug overlay of the hitbox (hidden by default)
	var dbg := MeshInstance3D.new()
	dbg.mesh = mesh_inst.mesh
	dbg.scale = Vector3(1.08, 1.08, 1.08)
	var dbg_mat := StandardMaterial3D.new()
	dbg_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.35)
	dbg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dbg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dbg.material_override = dbg_mat
	dbg.visible = false
	pivot.add_child(dbg)

	zone_nodes[zone_name] = pivot
	hitbox_nodes[zone_name] = area
	hitbox_debug_nodes[zone_name] = dbg

func _box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	return mi

func _sphere_mesh(r: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	mi.mesh = sm
	mi.material_override = _mat(color)
	return mi

func _capsule_mesh(r: float, h: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = _mat(color)
	return mi

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m

func _box_shape(size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	return cs

func _sphere_shape(r: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = r
	cs.shape = sp
	return cs

func _capsule_shape(r: float, h: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	cs.shape = cap
	return cs

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
			var d: float = weapon.splash_damage * falloff
			health.apply_damage(zone, d, weapon.sever_power)

func _on_zone_severed(zone: String) -> void:
	var node: Node3D = zone_nodes.get(zone)
	if node == null:
		return

	# Hide the zone and dependents, disable their hitboxes
	var to_hide := _get_dependent_zones(zone)
	to_hide.append(zone)
	for z in to_hide:
		var zn: Node3D = zone_nodes.get(z)
		if zn:
			zn.visible = false
		var hb: Area3D = hitbox_nodes.get(z)
		if hb:
			hb.collision_layer = 0
		var dbg: MeshInstance3D = hitbox_debug_nodes.get(z)
		if dbg:
			dbg.visible = false
		_collapse_bone(z)

	# Spawn detached limb rigid body (position only valid once in tree)
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
		# Hide entire body; gibs handled by TestStand
		visible = false
	else:
		# Simple ragdoll sim: tilt the body
		is_ragdoll = true
		_do_ragdoll_fall()

func _do_ragdoll_fall() -> void:
	if _ragdoll_tween and _ragdoll_tween.is_running():
		_ragdoll_tween.kill()
	_ragdoll_tween = create_tween()
	_ragdoll_tween.set_parallel(true)
	_ragdoll_tween.tween_property(self, "rotation:z", randf_range(1.2, 1.6) * sign(randf_range(-1, 1)), 0.4)
	_ragdoll_tween.tween_property(self, "position:y", -0.3, 0.4)

func reset() -> void:
	# Stop any in-flight ragdoll animation
	if _ragdoll_tween and _ragdoll_tween.is_running():
		_ragdoll_tween.kill()

	# Remove detached limbs
	for rb in detached_limbs:
		if is_instance_valid(rb):
			rb.queue_free()
	detached_limbs.clear()

	# Restore visibility, hitboxes, and skeleton pose
	for zone in zone_nodes:
		zone_nodes[zone].visible = true
	for zone in hitbox_nodes:
		hitbox_nodes[zone].collision_layer = 2
	_restore_all_bones()

	# Restore position/rotation
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
