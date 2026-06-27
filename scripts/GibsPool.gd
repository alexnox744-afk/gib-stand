class_name GibsPool
extends Node3D

const MAX_GIBS := 40
const SLEEP_AFTER := 4.5

var _pool: Array[RigidBody3D] = []
var _active: Array[Dictionary] = []
var blood_pool: BloodPool   # для кровавого следа от летящих гибов (может быть null)

func _ready() -> void:
	_fill_pool()

func _fill_pool() -> void:
	for i in MAX_GIBS:
		var rb := _make_gib()
		rb.visible = false
		rb.freeze = true
		add_child(rb)
		_pool.append(rb)

func _make_gib() -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = 0.5
	rb.gravity_scale = 2.0

	var colors := [Color(0.55, 0.07, 0.07), Color(0.45, 0.08, 0.06), Color(0.35, 0.05, 0.05)]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colors[randi() % colors.size()]
	mat.roughness = 0.9

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.material_override = mat

	var shape_idx := randi() % 4
	match shape_idx:
		0:
			var sz := Vector3(0.15, 0.1, 0.12)
			rb.add_child(_box_shape(sz))
			var bm := BoxMesh.new()
			bm.size = sz
			mesh_inst.mesh = bm
		1:
			var sz := Vector3(0.2, 0.08, 0.15)
			rb.add_child(_box_shape(sz))
			var bm := BoxMesh.new()
			bm.size = sz
			mesh_inst.mesh = bm
		2:
			rb.add_child(_capsule_shape(0.06, 0.18))
			var cm := CapsuleMesh.new()
			cm.radius = 0.06
			cm.height = 0.18
			mesh_inst.mesh = cm
		3:
			rb.add_child(_sphere_shape(0.09))
			var sm := SphereMesh.new()
			sm.radius = 0.09
			sm.height = 0.18
			mesh_inst.mesh = sm

	rb.add_child(mesh_inst)
	return rb

func _box_shape(sz: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	return cs

func _capsule_shape(r: float, h: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	cs.shape = cap
	return cs

func _sphere_shape(r: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = r
	cs.shape = sp
	return cs

func spawn_gibs(origin: Vector3, direction: Vector3, force: float, count: int = 8) -> void:
	for i in count:
		if _pool.is_empty():
			_recycle_oldest()
		if _pool.is_empty():
			return
		var rb: RigidBody3D = _pool.pop_back()
		rb.global_position = origin + Vector3(randf_range(-0.2, 0.2), randf_range(0, 0.3), randf_range(-0.2, 0.2))
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.freeze = false
		rb.visible = true

		var spread := direction + Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)) * 0.8
		spread = spread.normalized()
		rb.apply_central_impulse(spread * force * randf_range(0.5, 1.5))
		rb.apply_torque_impulse(Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)))

		_active.append({"rb": rb, "timer": SLEEP_AFTER, "drip": randf_range(0.03, 0.1)})

func _process(delta: float) -> void:
	var done := []
	for entry in _active:
		entry["timer"] -= delta
		if entry["timer"] <= 0:
			done.append(entry)
			continue
		# Кровавый след: пока гиб быстро летит, роняет капли по траектории.
		if blood_pool != null:
			var rb: RigidBody3D = entry["rb"]
			entry["drip"] = float(entry["drip"]) - delta
			if float(entry["drip"]) <= 0.0:
				entry["drip"] = randf_range(0.03, 0.1)
				if rb.linear_velocity.length() > 1.5:
					blood_pool.drip(rb.global_position)
	for entry in done:
		_active.erase(entry)
		var rb: RigidBody3D = entry["rb"]
		rb.freeze = true
		rb.visible = false
		_pool.append(rb)

func _recycle_oldest() -> void:
	if _active.is_empty():
		return
	var oldest: Dictionary = _active.pop_front()
	var rb: RigidBody3D = oldest["rb"]
	rb.freeze = true
	rb.visible = false
	_pool.append(rb)

func clear_all() -> void:
	for entry in _active:
		var rb: RigidBody3D = entry["rb"]
		rb.freeze = true
		rb.visible = false
		_pool.append(rb)
	_active.clear()

func active_count() -> int:
	return _active.size()
