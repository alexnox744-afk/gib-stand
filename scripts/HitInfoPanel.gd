class_name HitInfoPanel
extends PanelContainer

var zone_label: Label
var damage_label: Label
var zone_hp_label: Label
var total_hp_label: Label
var status_label: Label

func _ready() -> void:
	var vb := VBoxContainer.new()
	add_child(vb)

	var title := Label.new()
	title.text = "--- HIT INFO ---"
	title.add_theme_font_size_override("font_size", 14)
	vb.add_child(title)

	zone_label = _make_label(vb, "Zone: —")
	damage_label = _make_label(vb, "Damage: —")
	zone_hp_label = _make_label(vb, "Zone HP: —")
	total_hp_label = _make_label(vb, "Total HP: —")
	status_label = _make_label(vb, "")
	status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3))

func _make_label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	parent.add_child(l)
	return l

func update_hit(result: Dictionary) -> void:
	if result.is_empty():
		return
	zone_label.text = "Zone: " + str(result.get("zone", "?"))
	damage_label.text = "Damage: %.1f" % result.get("damage", 0.0)
	var zh_before: float = result.get("zone_hp_before", 0)
	var zh_after: float = result.get("zone_hp_after", 0)
	zone_hp_label.text = "Zone HP: %.0f → %.0f" % [zh_before, zh_after]
	var th_before: float = result.get("total_hp_before", 0)
	var th_after: float = result.get("total_hp_after", 0)
	total_hp_label.text = "Total HP: %.0f → %.0f" % [th_before, th_after]

	var status := ""
	if result.get("overkill", false):
		status = "OVERKILL — GIBS!"
	elif result.get("died", false):
		status = "DEAD — RAGDOLL"
	elif result.get("severed", false):
		status = "SEVERED: " + str(result.get("zone", ""))
	status_label.text = status
