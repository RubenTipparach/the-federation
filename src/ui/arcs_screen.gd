extends HBoxContainer

## The mounts and arcs screen: the 12 sector wheel, the mount list with
## isolation, derived arc stats, and the special override demo. Reads the same
## session fit the fitting screen edits, through the same ShipFit code.

signal design_changed

const MOUNT_ITEM := preload("res://scenes/ui/mount_arc_item.tscn")

var session: Session
var _isolated: String = ""
var _swapped_mount: String = ""
var _swapped_prev: String = ""
var _swapped_hull: String = ""


func bind_session(p_session: Session) -> void:
	session = p_session
	$Right/MountsPanel/V/ShowAll.pressed.connect(_on_show_all)
	$Right/OverridePanel/V/Swap.pressed.connect(_on_swap)
	refresh()


## Called by main whenever the fit changes on any screen.
func refresh() -> void:
	if session == null:
		return
	# A hull change from another screen invalidates the override swap state:
	# the remembered mount belongs to the old hull, and undoing onto the new
	# hull would refit the wrong mount or fail legality.
	if not _swapped_mount.is_empty() and _swapped_hull != session.fit.hull_id:
		_swapped_mount = ""
		_swapped_prev = ""
	if _isolated != "" and not session.fit.slots.has(_isolated):
		_isolated = ""
	_rebuild_mounts()
	_refresh_wheel()


func _rebuild_mounts() -> void:
	var list: VBoxContainer = $Right/MountsPanel/V/Scroll/MountList
	for child in list.get_children():
		child.queue_free()
	for mount in session.fit.mounts():
		var item: Button = MOUNT_ITEM.instantiate()
		list.add_child(item)
		item.setup(mount, session.fit)
		item.button_pressed = _isolated == String(mount["id"])
		item.isolate.connect(_on_isolate)


func _refresh_wheel() -> void:
	$WheelPanel/V/Wheel.show_fit(session.fit, _isolated)
	$WheelPanel/V/Head.text = "FIRING ARCS  %s" % String(
		session.fit.hull()["name"]).to_upper()
	var d: Dictionary = session.fit.derived()
	var blind_line: String = "Blind bearing  %s" % String(d["blind_label"])
	$Right/DerivedPanel/V/Body.text = "\n".join([
		"Sectors covered  %d / %d" % [int(d["covered"]), int(d["total_sectors"])],
		blind_line,
		"Mounts fitted  %d / %d" % [int(d["mounts_fitted"]), int(d["mount_count"])],
		"Alpha into bow  %d" % int(d["alpha_bow"]),
		"Alpha into port quarter  %d" % session.fit.alpha_into(8),
	])
	_refresh_swap_button()


func _on_isolate(mount_id: String) -> void:
	_isolated = "" if _isolated == mount_id else mount_id
	_rebuild_mounts()
	_refresh_wheel()


func _on_show_all() -> void:
	_isolated = ""
	_rebuild_mounts()
	_refresh_wheel()


## Swap a special weapon into the first mount that takes it, or restore what
## was there. Uses the ordinary fitting path, so legality still applies.
func _on_swap() -> void:
	if not _swapped_mount.is_empty():
		session.fit.set_slot(_swapped_mount, _swapped_prev)
		_swapped_mount = ""
		_swapped_prev = ""
	else:
		for mount in session.fit.mounts():
			var mount_id: String = String(mount["id"])
			if String(session.fit.slots.get(mount_id, "")) == "omni":
				continue
			if session.fit.is_legal(mount, Catalog.weapon("omni")):
				_swapped_prev = String(session.fit.slots.get(mount_id, ""))
				if session.fit.set_slot(mount_id, "omni"):
					_swapped_mount = mount_id
					_swapped_hull = session.fit.hull_id
					break
	design_changed.emit()
	refresh()


func _refresh_swap_button() -> void:
	if _swapped_mount.is_empty():
		$Right/OverridePanel/V/Swap.text = "Refit: Omni Emitter (special)"
	else:
		var prev_name: String = "empty"
		if not _swapped_prev.is_empty():
			prev_name = String(Catalog.weapon(_swapped_prev)["name"])
		$Right/OverridePanel/V/Swap.text = "Undo refit on %s (back to %s)" % [
			_swapped_mount, prev_name]
