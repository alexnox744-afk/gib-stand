class_name DecalPool
extends Node3D

const MAX_DECALS := 120

# Приоритет вытеснения при переполнении: дешёвые пятна на полу уходят первыми,
# раны на теле и культи держатся дольше всех.
const PRIO_LOW := 0      # капельные пятна на полу
const PRIO_NORMAL := 1   # лужи под телом
const PRIO_HIGH := 2     # раны на теле, культи

# Подсыхание: свежая кровь ярче и краснее, со временем темнеет в бурую, под
# конец жизни тускнеет в ноль и декаль уходит обратно в пул.
const DRY_TIME := 4.0                       # за сколько секунд кровь «подсыхает»
const FADE_TIME := 2.0                      # затухание в конце жизни
const FRESH_MOD := Color(1.3, 1.0, 1.0)     # свежая — ярче-краснее
const DRY_MOD := Color(0.5, 0.42, 0.38)     # подсохшая — тёмная бурая
# Сколько живёт декаль до возврата в пул — важные держатся дольше.
const LIFE_LOW := 8.0
const LIFE_NORMAL := 16.0
const LIFE_HIGH := 30.0

var _pool: Array[Decal] = []
var _active: Array[Decal] = []
var _albedo: GradientTexture2D

func _ready() -> void:
	_albedo = _make_blob_texture()
	_fill_pool()

func _life_for(priority: int) -> float:
	match priority:
		PRIO_LOW:
			return LIFE_LOW
		PRIO_HIGH:
			return LIFE_HIGH
		_:
			return LIFE_NORMAL

# Старение крови: подсыхание цвета, затем затухание и возврат в пул.
func _process(delta: float) -> void:
	var i := _active.size() - 1
	while i >= 0:
		var d := _active[i]
		if not is_instance_valid(d):
			_active.remove_at(i)
			i -= 1
			continue
		var age := float(d.get_meta("age", 0.0)) + delta
		d.set_meta("age", age)
		var mod := FRESH_MOD.lerp(DRY_MOD, clampf(age / DRY_TIME, 0.0, 1.0))
		var max_life := float(d.get_meta("max_life", LIFE_NORMAL))
		if age >= max_life:
			var f := (age - max_life) / FADE_TIME
			if f >= 1.0:
				_active.remove_at(i)
				_return_to_self(d)
				d.visible = false
				_pool.append(d)
				i -= 1
				continue
			mod.a = 1.0 - f
		d.modulate = mod
		i -= 1

func _make_blob_texture() -> GradientTexture2D:
	# Soft radial dark-red splat, generated so decals are visible without art.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.45, 0.02, 0.02, 0.9))
	grad.set_color(1, Color(0.4, 0.02, 0.02, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

func _fill_pool() -> void:
	for i in MAX_DECALS:
		var d := Decal.new()
		d.size = Vector3(0.3, 0.4, 0.3)
		d.texture_albedo = _albedo
		d.visible = false
		add_child(d)
		_pool.append(d)

func spawn(pos: Vector3, normal: Vector3, target: Node3D = null, size: float = -1.0, priority: int = PRIO_NORMAL) -> void:
	var d: Decal
	if _pool.is_empty():
		d = _evict()
		_return_to_self(d)
	else:
		d = _pool.pop_back()
	d.set_meta("prio", priority)
	d.set_meta("age", 0.0)
	d.set_meta("max_life", _life_for(priority))
	d.modulate = FRESH_MOD

	# Build a basis whose local +Y aligns with the surface normal,
	# because a Decal projects along its local Y axis.
	var y := normal.normalized()
	var seed_axis := Vector3.RIGHT
	if absf(y.dot(seed_axis)) > 0.99:
		seed_axis = Vector3.FORWARD
	var z := seed_axis.cross(y).normalized()
	var x := y.cross(z).normalized()
	var splat_basis := Basis(x, y, z)
	# Random spin around the normal for variety
	splat_basis = splat_basis.rotated(y, randf() * TAU)

	d.global_transform = Transform3D(splat_basis, pos + y * 0.05)

	# size >= 0 → задан вызывающим (масштаб по урону) с лёгким джиттером,
	# иначе старое случайное пятно.
	var sz: float
	if size > 0.0:
		sz = size * randf_range(0.9, 1.1)
	else:
		sz = randf_range(0.15, 0.4)
	d.size = Vector3(sz, 0.4, sz)
	d.visible = true
	_active.append(d)

	# Reparent to the hit bone so the decal follows the body into ragdoll.
	# global_transform is already set, so reparent(keep=true) bakes the right
	# local transform relative to the new parent.
	if target != null and is_instance_valid(target):
		d.reparent(target, true)

# Выбираем, какую активную декаль переиспользовать при переполнении: сначала
# самую старую дешёвую (пятно на полу), затем лужу, раны трогаем в последнюю
# очередь — так стены ран не «съедаются» брызгами.
func _evict() -> Decal:
	for prio in [PRIO_LOW, PRIO_NORMAL]:
		for i in _active.size():
			if int(_active[i].get_meta("prio", PRIO_NORMAL)) == prio:
				return _active.pop_at(i)
	return _active.pop_front()

# Возвращаем в пул все активные декали, прицепленные к узлу, ПЕРЕД его
# удалением — иначе queue_free родителя утащит их с собой и слоты пула утекут.
func reclaim_from(node: Node3D) -> void:
	if node == null:
		return
	var i := _active.size() - 1
	while i >= 0:
		var d := _active[i]
		if is_instance_valid(d) and node.is_ancestor_of(d):
			_active.remove_at(i)
			d.reparent(self, false)
			d.visible = false
			_pool.append(d)
		i -= 1

func _return_to_self(d: Decal) -> void:
	if d.get_parent() != self:
		d.reparent(self, false)

func clear_all() -> void:
	for d in _active:
		if not is_instance_valid(d):
			continue
		_return_to_self(d)
		d.visible = false
		_pool.append(d)
	_active.clear()

func active_count() -> int:
	return _active.size()
