class_name DetachedLimb
extends RigidBody3D

# Оторванная часть тела, по которой можно стрелять: попадание её ТОЛКАЕТ, а
# когда целостность падает до нуля (или прилетает мощный взрыв) — конечность
# ПЕРЕМАЛЫВАЕТСЯ в гибы и удаляется. Гибы и оторванные части — разные сущности:
# здесь это переход одной в другую (цельная часть → фарш) под достаточным уроном.

const CAP_RADIUS := 0.08
const CAP_HEIGHT := 0.3

var integrity: float = 50.0
var _spent: bool = false   # уже перемолота, ждёт удаления — больше не реагирует

# Area3D-хитбокс на слое 2 (как у зон тела), чтобы тот же луч стрельбы ловил
# конечность. Сама капсула физики живёт на слое 1 и падает на платформу.
func setup_hitbox() -> void:
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("detached_limb", true)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_RADIUS
	cap.height = CAP_HEIGHT
	cs.shape = cap
	area.add_child(cs)
	add_child(area)

# Толчок от попадания. Возвращает true ровно один раз — в момент перемола
# (integrity <= 0). Защищает от двойного перемола несколькими пеллетами/лучами
# одного залпа в том же кадре (queue_free отложен до конца кадра).
func take_hit(dir: Vector3, damage: float, force: float) -> bool:
	if _spent:
		return false
	var d := dir.normalized()
	apply_central_impulse(d * force + Vector3(randf_range(-1, 1), randf_range(0.4, 1.4), randf_range(-1, 1)))
	apply_torque_impulse(Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))
	integrity -= damage
	if integrity <= 0.0:
		_spent = true
		return true
	return false
