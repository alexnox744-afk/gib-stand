class_name HealthComponent
extends Node

signal health_changed(zone: String, old_hp: float, new_hp: float)
signal zone_severed(zone: String)
signal died(overkill: bool)
signal bled_out                      # смерть именно от кровотечения (отложенная)
signal incapacitated                 # функционально мёртв (не может действовать)
signal reset_done

# ─────────────────────────────────────────────────────────────
# Аркадная модель урона — ЕДИНАЯ система смерти от расчленёнки через bleed:
#   • Общий пул (current_hp) — главная "жизнь". 0 → смерть (регдол).
#   • ЛЮБОЙ отрыв включает кровотечение (bleed_rate, HP/сек из пула). Это
#     единственный механизм гибели от потери частей тела:
#       – голова: порог по head_damage → ОЧЕНЬ сильный bleed (~0.5с до смерти);
#       – руки:   свой HP → сильный bleed (срезает остаток пула за пару секунд).
#     Bleed складывается за каждую оторванную зону.
#   • Ноги — урон копится в пул, отрываются только В МОМЕНТ смерти.
#   • Голова/торс/таз/ноги также бьют прямо по пулу (BODY_DRAIN).
# ─────────────────────────────────────────────────────────────

const MAX_HP := 100.0

const ALL_ZONES := [
	"head", "torso",
	"upper_arm_L", "upper_arm_R", "lower_arm_L", "lower_arm_R",
	"thigh_L", "thigh_R", "shin_L", "shin_R",
]

const ARM_ZONES := ["upper_arm_L", "upper_arm_R", "lower_arm_L", "lower_arm_R"]
const LEG_ZONES := ["thigh_L", "thigh_R", "shin_L", "shin_R"]

# Кровотечение, которое включает отрыв зоны (HP/сек, сливается из общего пула).
# Голова — экстремальное (~0.5с до смерти). Руки — сильное, но не мгновенное.
const SEVER_BLEED := {
	"head": 100.0,                                # ~0.5с с остатка пула после декапа
	"upper_arm_L": 45.0, "upper_arm_R": 45.0,     # ~2с с почти полного пула
	"lower_arm_L": 35.0, "lower_arm_R": 35.0,
}

# Отдельный HP рук — обнулился → рука отрывается. К смерти не ведёт.
const ARM_HP := {
	"upper_arm_L": 35.0, "upper_arm_R": 35.0,
	"lower_arm_L": 25.0, "lower_arm_R": 25.0,
}

# Накопленный урон по голове для декапитации.
const HEAD_SEVER := 30.0

# Сколько надо накопить по ноге, чтобы она отвалилась — НО только при смерти.
const LEG_SEVER := {
	"thigh_L": 45.0, "thigh_R": 45.0,
	"shin_L": 30.0, "shin_R": 30.0,
}

# Доля урона зоны, уходящая в общий пул смерти.
const BODY_DRAIN := {
	"head": 1.6,                                  # хедшоты больно
	"torso": 1.0,
	"thigh_L": 0.8, "thigh_R": 0.8,
	"shin_L": 0.6, "shin_R": 0.6,
	"upper_arm_L": 0.15, "upper_arm_R": 0.15,     # руки еле задевают пул
	"lower_arm_L": 0.1, "lower_arm_R": 0.1,
}

var max_hp: float = MAX_HP
var current_hp: float = MAX_HP        # общий пул (имя сохранено для совместимости)
var arm_hp: Dictionary = {}
var leg_damage: Dictionary = {}       # накопленный урон по ногам (реализуется при смерти)
var head_damage: float = 0.0
var severed_zones: Array[String] = []
var is_dead: bool = false
var bleed_rate: float = 0.0

# Переключатель на будущее (для боёвки): true — отрыв головы СРАЗУ делает врага
# функционально мёртвым (повод заблокировать ИИ/ввод), а видимая смерть всё равно
# доигрывается кровотечением. false (по умолчанию) = кинематографично: безголовое
# тело ещё "живо" те ~0.5с, пока истекает кровью.
var incapacitate_on_decap: bool = false
var is_incapacitated: bool = false   # не может действовать (декап при флаге, либо смерть)

func _ready() -> void:
	_init_state()

func _init_state() -> void:
	current_hp = max_hp
	arm_hp.clear()
	for z in ARM_HP:
		arm_hp[z] = ARM_HP[z]
	leg_damage.clear()
	for z in LEG_ZONES:
		leg_damage[z] = 0.0
	head_damage = 0.0
	severed_zones.clear()
	is_dead = false
	bleed_rate = 0.0
	is_incapacitated = false

func apply_damage(zone: String, raw_damage: float, sever_power: float = 1.0) -> Dictionary:
	if is_dead or raw_damage <= 0.0:
		return {}

	var pool_before: float = current_hp
	var result := {
		"zone": zone,
		"damage": raw_damage,
		"zone_hp_before": _zone_hp(zone),
		"zone_hp_after": _zone_hp(zone),
		"total_hp_before": pool_before,
		"total_hp_after": pool_before,
		"severed": false,
		"died": false,
		"overkill": false,
	}

	# 1) Урон в общий пул по маршруту зоны.
	var drain: float = raw_damage * float(BODY_DRAIN.get(zone, 1.0))
	current_hp = maxf(0.0, current_hp - drain)
	result["total_hp_after"] = current_hp
	health_changed.emit(zone, pool_before, current_hp)

	# 2) Зональная логика отрыва. Сам отрыв смерть НЕ вызывает — он включает
	#    кровотечение (в _sever), а добивает уже _process опустошением пула.
	if zone == "head":
		head_damage += raw_damage * sever_power
		if "head" not in severed_zones and head_damage >= HEAD_SEVER:
			_sever("head", result)     # мощнейший bleed → смерть через ~0.5с
			if incapacitate_on_decap:
				_incapacitate()        # опц.: сразу "функционально мёртв"
	elif zone in ARM_ZONES:
		var ah: float = float(arm_hp.get(zone, 0.0))
		arm_hp[zone] = maxf(0.0, ah - raw_damage)
		result["zone_hp_after"] = arm_hp[zone]
		if zone not in severed_zones and arm_hp[zone] <= 0.0:
			_sever(zone, result)       # рука отваливается, но НЕ убивает
	elif zone in LEG_ZONES:
		leg_damage[zone] = float(leg_damage.get(zone, 0.0)) + raw_damage * sever_power
		# нога не отрывается пока жив — решается в _die()

	# 3) Оверкилл: одиночный удар намного больше остатка → гибы.
	if not is_dead and current_hp <= 0.0 and drain >= pool_before + max_hp * 0.5:
		_die(true, result)
		return result

	# 4) Смерть от опустошения пула → регдол.
	if not is_dead and current_hp <= 0.0:
		_die(false, result)

	return result

func _sever(zone: String, result: Dictionary) -> void:
	if zone in severed_zones:
		return
	severed_zones.append(zone)
	result["severed"] = true
	bleed_rate += float(SEVER_BLEED.get(zone, 0.0))
	zone_severed.emit(zone)

func _process(delta: float) -> void:
	if bleed_rate <= 0.0 or is_dead:
		return
	var old_hp := current_hp
	current_hp = maxf(0.0, current_hp - bleed_rate * delta)
	health_changed.emit("torso", old_hp, current_hp)
	if current_hp <= 0.0:
		var dummy := {}
		_die(false, dummy)
		bled_out.emit()

func _incapacitate() -> void:
	if is_incapacitated:
		return
	is_incapacitated = true
	incapacitated.emit()

func _die(overkill: bool, result: Dictionary) -> void:
	if is_dead:
		return
	is_dead = true
	_incapacitate()              # смерть всегда = функционально мёртв
	bleed_rate = 0.0
	result["died"] = true
	result["overkill"] = overkill
	# При обычной смерти ноги, по которым настреляли, отваливаются именно сейчас.
	# При оверкилле всё тело и так разлетается в гибы — отдельно не рвём.
	if not overkill:
		for lz in LEG_ZONES:
			if lz not in severed_zones and float(leg_damage.get(lz, 0.0)) >= float(LEG_SEVER[lz]):
				severed_zones.append(lz)
				zone_severed.emit(lz)
	died.emit(overkill)

func _zone_hp(zone: String) -> float:
	if zone in ARM_ZONES:
		return float(arm_hp.get(zone, 0.0))
	return current_hp

func apply_dead_hit(zone: String, raw_damage: float, sever_power: float = 1.0) -> Dictionary:
	if not is_dead or raw_damage <= 0.0 or zone in severed_zones:
		return {}
	var result := {
		"zone": zone, "damage": raw_damage,
		"zone_hp_before": 0.0, "zone_hp_after": 0.0,
		"total_hp_before": 0.0, "total_hp_after": 0.0,
		"severed": false, "died": false, "overkill": false,
	}
	if zone == "head":
		head_damage += raw_damage * sever_power
		if head_damage >= HEAD_SEVER:
			_sever("head", result)
	elif zone in ARM_ZONES:
		var ah := float(arm_hp.get(zone, 0.0))
		arm_hp[zone] = maxf(0.0, ah - raw_damage)
		if arm_hp[zone] <= 0.0:
			_sever(zone, result)
	elif zone in LEG_ZONES:
		leg_damage[zone] = float(leg_damage.get(zone, 0.0)) + raw_damage * sever_power
		if float(leg_damage.get(zone, 0.0)) >= float(LEG_SEVER[zone]):
			_sever(zone, result)
	return result

func apply_splash_damage(zones_in_radius: Array, damage: float, sever_power: float = 1.0) -> void:
	for zone in zones_in_radius:
		apply_damage(zone, damage, sever_power)

func reset() -> void:
	_init_state()
	reset_done.emit()

func is_zone_severed(zone: String) -> bool:
	return zone in severed_zones
