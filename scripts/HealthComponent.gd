class_name HealthComponent
extends Node

signal health_changed(zone: String, old_hp: float, new_hp: float)
signal zone_severed(zone: String)
signal died(overkill: bool)
signal reset_done

const ZONE_HP := {
	"head": 30.0,
	"torso": 100.0,
	"upper_arm_L": 40.0,
	"upper_arm_R": 40.0,
	"lower_arm_L": 30.0,
	"lower_arm_R": 30.0,
	"thigh_L": 50.0,
	"thigh_R": 50.0,
	"shin_L": 35.0,
	"shin_R": 35.0,
}

const SEVER_THRESHOLD := {
	"head": 25.0,
	"upper_arm_L": 30.0,
	"upper_arm_R": 30.0,
	"lower_arm_L": 25.0,
	"lower_arm_R": 25.0,
	"thigh_L": 40.0,
	"thigh_R": 40.0,
	"shin_L": 30.0,
	"shin_R": 30.0,
}

const SEVERABLE := ["head", "upper_arm_L", "upper_arm_R", "lower_arm_L", "lower_arm_R",
	"thigh_L", "thigh_R", "shin_L", "shin_R"]

const DAMAGE_MULTIPLIER := {
	"head": 2.5,
	"torso": 1.0,
	"upper_arm_L": 0.8,
	"upper_arm_R": 0.8,
	"lower_arm_L": 0.7,
	"lower_arm_R": 0.7,
	"thigh_L": 0.9,
	"thigh_R": 0.9,
	"shin_L": 0.75,
	"shin_R": 0.75,
}

var max_hp: float = 300.0
var current_hp: float = 300.0
var zone_hp: Dictionary = {}
var severed_zones: Array[String] = []
var is_dead: bool = false

func _ready() -> void:
	_init_zones()

func _init_zones() -> void:
	zone_hp.clear()
	for zone in ZONE_HP:
		zone_hp[zone] = ZONE_HP[zone]

func apply_damage(zone: String, raw_damage: float, sever_power: float = 1.0) -> Dictionary:
	if is_dead:
		return {}

	var multiplier: float = DAMAGE_MULTIPLIER.get(zone, 1.0)
	var actual_damage: float = raw_damage * multiplier

	var old_zone_hp: float = zone_hp.get(zone, 0.0)
	var old_total: float = current_hp

	zone_hp[zone] = maxf(0.0, old_zone_hp - actual_damage)
	current_hp = maxf(0.0, current_hp - actual_damage)

	health_changed.emit(zone, old_zone_hp, zone_hp[zone])

	var result := {
		"zone": zone,
		"damage": actual_damage,
		"zone_hp_before": old_zone_hp,
		"zone_hp_after": zone_hp[zone],
		"total_hp_before": old_total,
		"total_hp_after": current_hp,
		"severed": false,
		"died": false,
		"overkill": false,
	}

	# Check overkill
	var overkill_threshold := max_hp * 0.5
	if actual_damage >= current_hp + overkill_threshold or (is_dead == false and current_hp <= 0 and actual_damage >= old_total * 1.5):
		is_dead = true
		result["died"] = true
		result["overkill"] = true
		died.emit(true)
		return result

	# Check sever
	if zone in SEVERABLE and zone not in severed_zones:
		var threshold: float = SEVER_THRESHOLD.get(zone, 9999.0)
		var accumulated: float = ZONE_HP.get(zone, 0.0) - zone_hp[zone]
		if accumulated * sever_power >= threshold:
			severed_zones.append(zone)
			result["severed"] = true
			zone_severed.emit(zone)

	# Check death
	if current_hp <= 0 and not is_dead:
		is_dead = true
		result["died"] = true
		died.emit(false)

	return result

func apply_splash_damage(zones_in_radius: Array, damage: float, sever_power: float = 1.0) -> void:
	for zone in zones_in_radius:
		apply_damage(zone, damage, sever_power)

func reset() -> void:
	current_hp = max_hp
	severed_zones.clear()
	is_dead = false
	_init_zones()
	reset_done.emit()

func get_zone_percent(zone: String) -> float:
	var max_z: float = ZONE_HP.get(zone, 1.0)
	return zone_hp.get(zone, 0.0) / max_z

func is_zone_severed(zone: String) -> bool:
	return zone in severed_zones
