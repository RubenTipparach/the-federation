extends Button

## One mount on the arcs screen. Pressing isolates its wedge on the wheel and
## reveals the mount's permitted field, which is how "the mount owns the arc"
## is made visible rather than asserted.

signal isolate(mount_id: String)

var mount_id: String = ""


func setup(mount: Dictionary, fit: ShipFit) -> void:
	mount_id = String(mount["id"])
	$Body/Title.text = "%s  %s" % [mount_id, String(mount["pos"])]
	Paint.tint($Body/Title, "font_color", Color.WHITE)
	var w: Dictionary = fit.weapon_in(mount_id)
	var lines: Array[String] = []
	lines.append("%s / permits %s" % [String(mount["size"]), " ".join(Array(mount["families"]))])
	lines.append("field %s" % Sectors.label_for_sectors(Catalog.to_int_array(mount["field"])))
	if w.is_empty():
		lines.append("empty")
	else:
		var line: String = "%s  rng %d  dmg %d" % [
			String(w["name"]), int(WeaponModel.max_range(w)), WeaponModel.max_damage(w)]
		if bool(w.get("special", false)) and w.has("override_field"):
			line += "  OVERRIDES to %s" % Sectors.label_for_sectors(fit.effective_field(mount))
		lines.append(line)
	$Body/Meta.text = "\n".join(lines)
	var overridden: bool = not w.is_empty() and bool(w.get("special", false))
	Paint.tint($Body/Meta, 
		"font_color", Palette.AMBER if overridden else Palette.DIM)
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func _on_pressed() -> void:
	isolate.emit(mount_id)
