class_name BloodPool
extends Node3D

# Пул капель крови. Раньше каждая капля была отдельным MeshInstance3D + tween +
# create_timer + queue_free — чейнган (10/с) и дробовик (8 пеллет) плодили
# десятки нод за миг. Здесь капли переиспользуются, а баллистика считается
# вручную в _process (без тысяч твинов). Долетев до пола, капля оставляет
# мини-декаль и возвращается в пул.

const MAX_DROPS := 220
const GRAVITY := 10.0       # совпадает со старым смещением -5*t² (0.5*g=5)
const FLOOR_Y := 0.01
const FLOOR_SPECK_CHANCE := 0.6

var decal_pool: DecalPool   # для пятен в точке приземления (может быть null)
var enable_specks: bool = true   # синхронно с тумблером Decals в UI

var _pool: Array[MeshInstance3D] = []
var _active: Array[Dictionary] = []

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.05, 0.05)
	mat.roughness = 0.9
	var mesh := SphereMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.04
	mesh.material = mat
	for _i in MAX_DROPS:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pool.append(mi)

# pos — точка вылета, dir — базовое направление струи, count — число капель.
func spawn_burst(pos: Vector3, dir: Vector3, count: int) -> void:
	var d := dir.normalized()
	for _i in count:
		# Вдоль направления (вес 1.5) + конус разброса, чтобы выстрел читался.
		var spread := (d * 1.5 + Vector3(
			randf_range(-0.7, 0.7),
			randf_range(-0.3, 0.7),
			randf_range(-0.7, 0.7)
		)).normalized()
		_spawn_one(pos, spread * randf_range(1.5, 6.0))

# Одиночная капля, срывающаяся с летящего гиба — почти без горизонтальной
# скорости, в основном падает вниз и оставляет пятно на полу.
func drip(pos: Vector3) -> void:
	_spawn_one(pos, Vector3(randf_range(-0.3, 0.3), randf_range(-0.4, 0.1), randf_range(-0.3, 0.3)))

func _spawn_one(pos: Vector3, vel: Vector3) -> void:
	var mi: MeshInstance3D
	if _pool.is_empty():
		# Пул исчерпан — переиспользуем самую старую активную каплю.
		var oldest: Dictionary = _active.pop_front()
		mi = oldest["node"]
	else:
		mi = _pool.pop_back()
	mi.visible = true
	mi.scale = Vector3.ONE
	mi.global_position = pos
	_active.append({
		"node": mi,
		"vel": vel,
		"t": 0.0,
		"life": randf_range(0.3, 0.6),
		"can_speck": pos.y > 0.05,
	})

func _process(delta: float) -> void:
	var i := _active.size() - 1
	while i >= 0:
		var d: Dictionary = _active[i]
		var mi: MeshInstance3D = d["node"]
		d["t"] = float(d["t"]) + delta
		var vel: Vector3 = d["vel"]
		vel.y -= GRAVITY * delta
		d["vel"] = vel
		mi.global_position += vel * delta

		if mi.global_position.y <= FLOOR_Y and vel.y < 0.0:
			# Приземлилась — пятно на полу и обратно в пул.
			if enable_specks and bool(d["can_speck"]) and decal_pool != null and randf() < FLOOR_SPECK_CHANCE:
				decal_pool.spawn(Vector3(mi.global_position.x, FLOOR_Y, mi.global_position.z),
					Vector3.UP, null, randf_range(0.14, 0.28), DecalPool.PRIO_LOW)
			_retire(i)
		elif float(d["t"]) >= float(d["life"]):
			_retire(i)
		else:
			# Гаснет в последние 45% жизни.
			var k := float(d["t"]) / float(d["life"])
			if k > 0.55:
				mi.scale = Vector3.ONE * maxf(1.0 - (k - 0.55) / 0.45, 0.0)
		i -= 1

func _retire(idx: int) -> void:
	var mi: MeshInstance3D = _active[idx]["node"]
	mi.visible = false
	_active.remove_at(idx)
	_pool.append(mi)

func clear_all() -> void:
	for d in _active:
		var mi: MeshInstance3D = d["node"]
		mi.visible = false
		_pool.append(mi)
	_active.clear()

func active_count() -> int:
	return _active.size()
