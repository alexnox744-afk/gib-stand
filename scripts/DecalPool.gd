class_name DecalPool
extends Node3D

const MAX_DECALS := 60

var _pool: Array[Decal] = []
var _active: Array[Decal] = []
var _mat: StandardMaterial3D

func _ready() -> void:
	_fill_pool()

func _fill_pool() -> void:
	for i in MAX_DECALS:
		var d := Decal.new()
		d.size = Vector3(0.3, 1.0, 0.3)
		d.visible = false
		add_child(d)
		_pool.append(d)

func spawn(pos: Vector3, normal: Vector3) -> void:
	var d: Decal
	if _pool.is_empty():
		d = _active.pop_front()
	else:
		d = _pool.pop_back()

	d.global_position = pos + normal * 0.01
	var up := Vector3.UP
	if abs(normal.dot(up)) > 0.99:
		up = Vector3.RIGHT
	d.look_at(pos + normal, up)
	d.rotate_object_local(Vector3.UP, PI)

	var sz := randf_range(0.15, 0.4)
	d.size = Vector3(sz, 1.0, sz)
	d.visible = true
	_active.append(d)

func clear_all() -> void:
	for d in _active:
		d.visible = false
		_pool.append(d)
	_active.clear()

func active_count() -> int:
	return _active.size()
