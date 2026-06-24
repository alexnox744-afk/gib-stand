class_name OrbitCamera
extends Node3D

@export var target: Node3D
@export var distance: float = 4.0
@export var min_distance: float = 1.5
@export var max_distance: float = 12.0
@export var sensitivity: float = 0.3
@export var zoom_speed: float = 0.5

var yaw: float = 0.0
var pitch: float = 20.0
var _orbiting: bool = false

func _ready() -> void:
	_update_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_orbiting = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distance = clampf(distance - zoom_speed, min_distance, max_distance)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = clampf(distance + zoom_speed, min_distance, max_distance)
				_update_camera()

	elif event is InputEventMouseMotion and _orbiting:
		yaw -= event.relative.x * sensitivity
		pitch = clampf(pitch - event.relative.y * sensitivity, -80.0, 80.0)
		_update_camera()

func _update_camera() -> void:
	var origin: Vector3 = target.global_position if target else global_position
	var rot := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	var offset := rot * Vector3(0, 0, distance)
	global_position = origin + offset
	look_at(origin, Vector3.UP)
