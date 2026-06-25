class_name DecalPool
extends Node3D

const MAX_DECALS := 60

var _pool: Array[Decal] = []
var _active: Array[Decal] = []
var _albedo: GradientTexture2D

func _ready() -> void:
	_albedo = _make_blob_texture()
	_fill_pool()

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

func spawn(pos: Vector3, normal: Vector3) -> void:
	var d: Decal
	if _pool.is_empty():
		d = _active.pop_front()
	else:
		d = _pool.pop_back()

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

	var sz := randf_range(0.15, 0.4)
	d.size = Vector3(sz, 0.4, sz)
	d.visible = true
	_active.append(d)

func clear_all() -> void:
	for d in _active:
		d.visible = false
		_pool.append(d)
	_active.clear()

func active_count() -> int:
	return _active.size()
