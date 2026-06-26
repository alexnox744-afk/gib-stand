class_name LimbHider
extends SkeletonModifier3D

# Прячем оторванные конечности на ОДНОМ skinned-меше, схлопывая scale кости в
# точку. Этот модификатор стоит в стеке ПОСЛЕ PhysicalBoneSimulator3D, поэтому
# переписывает scale, который симулятор регдола каждый кадр возвращает в 1.
# Благодаря этому оторванная часть остаётся невидимой и в регдоле, и при
# добивании трупа (раньше симуляция "надувала" её обратно).

var hidden_bones: Dictionary = {}   # bone_idx -> true

func hide_bone(bone_idx: int) -> void:
	if bone_idx >= 0:
		hidden_bones[bone_idx] = true

func clear_hidden() -> void:
	hidden_bones.clear()

func _process_modification() -> void:
	if hidden_bones.is_empty():
		return
	var skel := get_skeleton()
	if skel == null:
		return
	# Трогаем только scale: позицию/поворот оставляет симулятор, поэтому
	# схлопнутая конечность сжимается в точку прямо в месте отрыва на регдоле.
	for b in hidden_bones:
		skel.set_bone_pose_scale(b, Vector3.ONE * 0.001)
