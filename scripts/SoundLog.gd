class_name SoundLog
extends CanvasLayer

# Replaces actual audio - logs what sound would have played

const MAX_ENTRIES := 12
const FADE_TIME := 3.0

var entries: Array = []
var vbox: VBoxContainer

func _ready() -> void:
	layer = 10
	vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	vbox.position = Vector2(-320, -260)
	vbox.size = Vector2(300, 240)
	vbox.alignment = BoxContainer.ALIGNMENT_END
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never block shooting
	add_child(vbox)

func play(sound_name: String) -> void:
	var label := Label.new()
	label.text = "♪ " + sound_name
	label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(label)
	entries.append({"label": label, "timer": FADE_TIME})

	if entries.size() > MAX_ENTRIES:
		var old: Dictionary = entries.pop_front()
		if is_instance_valid(old["label"]):
			old["label"].queue_free()

func _process(delta: float) -> void:
	var to_remove := []
	for entry in entries:
		entry["timer"] -= delta
		if not is_instance_valid(entry["label"]):
			to_remove.append(entry)
			continue
		var t: float = entry["timer"] / FADE_TIME
		entry["label"].modulate.a = clampf(t * 2.0, 0.0, 1.0)
		if entry["timer"] <= 0:
			entry["label"].queue_free()
			to_remove.append(entry)
	for e in to_remove:
		entries.erase(e)
