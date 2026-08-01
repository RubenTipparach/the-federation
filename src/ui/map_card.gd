extends Button

## One arena on the skirmish screen's map picker. The card IS the preview: it
## carries a plan of a real placement rather than a stylised icon, so choosing
## Debris Belt means having seen what a debris belt looks like.
##
## The plan is drawn from a fixed preview seed, not from the seed the battle
## will use, because the battle's seed does not exist until Begin is pressed.
## That is why there is no regenerate button: there would be nothing to
## regenerate.

signal chosen(map_id: String)

var map_id: String = ""


func setup(p_map_id: String) -> void:
	map_id = p_map_id
	var spec: Dictionary = Catalog.map(map_id)
	# The card is narrow and the face is a fixed size bitmap, so the card
	# wears the short name and everything with room wears the full one.
	$V/Name.text = String(spec["short"]).to_upper()
	tooltip_text = "%s\n%s" % [String(spec["name"]), String(spec["blurb"])]

	# Built through the same Terrain the battle will build, from the same
	# recipe, so the preview cannot describe an arena the game would not make.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(Catalog.tuning()["skirmish"]["preview_seed"])
	var starts: Array[Vector2] = Battle.start_positions()
	$V/Plan.show_terrain(Terrain.create(map_id, rng, starts), starts)

	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func paint_selected(selected: bool) -> void:
	button_pressed = selected
	$V/Name.add_theme_color_override("font_color",
		Palette.CYAN if selected else Palette.DIM)


func _on_pressed() -> void:
	chosen.emit(map_id)
