extends PanelContainer

## One mount row on the fitting screen. The selector only ever offers weapons
## the fitting validator accepts, so an illegal fit cannot be expressed.

signal slot_changed(mount_id: String, weapon_id: String)

var _mount: Dictionary = {}
var _options: Array[String] = []


func setup(mount: Dictionary, fit: ShipFit) -> void:
	_mount = mount
	var mount_id: String = String(mount["id"])
	$Body/Title.text = "%s  %s" % [mount_id, String(mount["pos"])]
	$Body/Title.add_theme_color_override("font_color", Color.WHITE)
	var families: Array = mount["families"]
	$Body/Meta.text = "%s / %s / field %s" % [
		String(mount["size"]),
		" ".join(families),
		Sectors.label_for_sectors(Catalog.to_int_array(mount["field"])),
	]
	$Body/Meta.add_theme_color_override("font_color", Palette.DIM)

	var selector: OptionButton = $Body/Weapon
	selector.clear()
	_options = fit.legal_weapons_for(mount)
	selector.add_item("Empty")
	var current: String = String(fit.slots.get(mount_id, ""))
	var select_index: int = 0
	for i in range(_options.size()):
		var w: Dictionary = Catalog.weapon(_options[i])
		var tag: String = "  [special]" if bool(w.get("special", false)) else ""
		selector.add_item("%s  rng %d dmg %d%s" % [
			String(w["name"]), int(WeaponModel.max_range(w)), WeaponModel.max_damage(w), tag])
		if _options[i] == current:
			select_index = i + 1
	selector.select(select_index)
	if not selector.item_selected.is_connected(_on_selected):
		selector.item_selected.connect(_on_selected)


func _on_selected(index: int) -> void:
	var weapon_id: String = "" if index == 0 else _options[index - 1]
	slot_changed.emit(String(_mount["id"]), weapon_id)
