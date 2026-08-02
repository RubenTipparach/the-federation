extends SceneTree

## CLAUDE.md 6.4, enforced: no panel and no viewport may change size because of
## what was written into it.
##
## The method is to be unreasonable on purpose. Every Label on the combat screen
## is handed a string far longer than any hull name, weapon or reading the game
## can produce, and then the columns and the 3D render target are measured. If
## a panel is a fixed rectangle the numbers do not move at all.
##
## Two process frames, not one. A minimum size change is deferred by a frame and
## the container sort it triggers is deferred by another, so a test that waits a
## single frame passes while the layout is still mid collapse.
##
## Measure `size`, never `get_combined_minimum_size()`. Once a maximum is set the
## combined minimum still reports the UNBOUNDED value, which reads like a failure
## and is not one: the maximum has priority and the node is laid out at the
## bounded size. That trap cost an hour to find, so it is written down here.

## Longer than any hull name, weapon name or numeric reading the game produces,
## and made of a repeating pattern so a partial write is obvious in a diff.
const ABSURD: String = "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"

var _checks: int = 0
var _failed: int = 0


func _ok(what: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got == want:
		print("  ok    %s  (%s)" % [what, str(got)])
	else:
		_failed += 1
		print("  FAIL  %s  (got %s, want %s)" % [what, str(got), str(want)])


func _stuff_every_label(node: Node) -> int:
	var n: int = 0
	if node is Label:
		(node as Label).text = ABSURD
		n += 1
	elif node is Button and not (node as Button).text.is_empty():
		(node as Button).text = ABSURD
		n += 1
	for child in node.get_children():
		n += _stuff_every_label(child)
	return n


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.show_tab("Combat")
	main._on_begin_battle()
	for i in range(20):
		await process_frame

	var c: Node = main.get_node("Root/Content/Combat")
	var left: Control = c.get_node("Left")
	var right: Control = c.get_node("Right")
	var mid: Control = c.get_node("Mid")
	var view: SubViewport = c.get_node("Mid/ViewPanel/Stack/ViewContainer/View")
	# The station strip and the panel beside it. Their widths are arithmetic on
	# the column's, so a mark or a readout that grew would show up here first.
	var tabs: Control = c.get_node("Right/FightStation/FightTabs")
	var station: Control = c.get_node("Right/FightStation/FightPanel")

	var before := {
		"left": left.size, "right": right.size, "mid": mid.size, "view": view.size,
		"tabs": tabs.size, "station": station.size,
	}
	print("")
	print("Layout, at rest")
	for key in before:
		print("  %-6s %s" % [key, str(before[key])])

	# The screen repaints from the ship every tick, so the absurd strings would
	# be overwritten immediately. Stopping the repaint is what makes the test
	# about layout rather than about who wrote last.
	c.set_physics_process(false)
	c.set_process(false)
	var stuffed: int = _stuff_every_label(c)
	await process_frame
	await process_frame
	await process_frame

	print("")
	print("Layout, after %d labels were handed %d characters each" % [stuffed, ABSURD.length()])
	_ok("the left column did not move", left.size, before["left"])
	_ok("the right column did not move", right.size, before["right"])
	_ok("the middle column did not move", mid.size, before["mid"])
	_ok("the 3D render target was not resized", view.size, before["view"])

	_ok("the station strip did not move", tabs.size, before["tabs"])
	_ok("the station panel did not move", station.size, before["station"])

	# The columns are pinned by a maximum, so this is what the rule actually
	# says: authored width, whatever is inside them.
	_ok("the left column is its authored width", int(left.size.x), 360)
	_ok("the right column is its authored width", int(right.size.x), 360)
	# 360 for the column, less 60 for the strip, less the 4 between them.
	_ok("the station strip is its authored width", int(tabs.size.x), 60)
	_ok("the station panel is what is left of the column", int(station.size.x), 296)

	print("")
	if _failed == 0:
		print("ALL LAYOUT CHECKS PASSED  (%d checks)" % _checks)
	else:
		print("LAYOUT CHECKS FAILED  (%d of %d)" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)
