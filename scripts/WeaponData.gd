class_name WeaponData
extends Resource

enum HitType { HITSCAN_SINGLE, HITSCAN_SPREAD, PROJECTILE_SPLASH, MELEE }

@export var weapon_name: String = "Unnamed"
@export var hit_type: HitType = HitType.HITSCAN_SINGLE
@export var damage: float = 10.0
@export var pellet_count: int = 1
@export var spread_angle: float = 0.0
@export var splash_radius: float = 0.0
@export var splash_damage: float = 0.0
@export var dismember_force: float = 5.0
@export var gib_on_direct_hit: bool = false
@export var sever_power: float = 1.0
@export var fire_rate: float = 3.0
@export var fire_sound: String = "fire_generic"
@export var impact_sound: String = "impact_flesh"
# Визуал взрыва для splash-оружия: цвет вспышки и пиковый масштаб шара.
@export var explosion_color: Color = Color(1.0, 0.6, 0.15, 0.9)
@export var explosion_scale: float = 7.0
