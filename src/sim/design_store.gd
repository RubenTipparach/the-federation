class_name DesignStore
extends RefCounted

## Where saved ship designs are kept, and how they are named.
##
## Deliberately the same shape as src/sim/replay_store.gd: a directory under
## user://, a filename that sorts chronologically and says what it holds, a
## listing newest first, and a one line description for a row. Two stores doing
## the same job should look the same, so neither has to be learned twice
## (CLAUDE.md 4.1). Both sit outside the UI so a headless tool can read the
## same files the settings panel shows (5.2).
##
## A design is a hull and what is fitted in each of its mounts, which is exactly
## what ShipFit holds, so this is a small file and should stay one.

const DIR: String = "user://designs"


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


## A name that sorts chronologically and says which hull it is, so the
## directory is readable without opening anything.
##
## The stamp lives in the filename and nowhere else, which is why there is no
## saved_at field in the body. Two copies of when something happened is two
## things that can disagree, and the one in the name is the one the sort uses.
static func name_for(fit: ShipFit, stamp: int) -> String:
	return "%d-%s.json" % [stamp, fit.hull_id]


static func save(fit: ShipFit, stamp: int) -> String:
	ensure_dir()
	var path: String = DIR + "/" + name_for(fit, stamp)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({"hull": fit.hull_id, "slots": fit.slots}, "\t"))
	return path


## The design in a saved file, or null if it cannot be trusted.
##
## Null rather than a best effort fit: a design that quietly came back as a
## different ship is worse than one that refuses to load, and the caller can
## say so in a row rather than putting the wrong thing in the player's hands.
##
## Rebuilt from the hull's defaults and then overwritten slot by slot through
## ShipFit.set_slot, which is the fitting validator. That means a design saved
## before a hull gained a mount still loads, with the new mount at whatever the
## hull says rather than empty, and a slot that has since become illegal is
## refused by the same code the fitting screen refuses it with rather than by a
## second check here.
static func read(path: String) -> ShipFit:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return null
	var hull_id: String = String((data as Dictionary).get("hull", ""))
	if not Catalog.hulls().has(hull_id):
		return null
	var fit: ShipFit = ShipFit.create_default(hull_id)
	var slots: Dictionary = (data as Dictionary).get("slots", {})
	for mount_id in slots:
		fit.set_slot(String(mount_id), String(slots[mount_id]))
	return fit


## When a design was saved, from its filename. Zero for a name that does not
## carry one, which sorts it last rather than crashing a listing.
static func stamp_of(path: String) -> int:
	var head: String = path.get_file().split("-")[0]
	return int(head) if head.is_valid_int() else 0


## Every saved design, newest first.
static func list_paths() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".json"):
			out.append(DIR + "/" + file)
	out.sort()
	out.reverse()
	return out


static func remove(path: String) -> bool:
	return DirAccess.remove_absolute(path) == OK


## A one line description for a list row: what the ship is, not what the file
## is. The date is appended by the caller, because only the caller knows the
## player's clock.
static func describe(fit: ShipFit) -> String:
	var h: Dictionary = fit.hull()
	return "%s / %d t / %d of %d mounts" % [
		String(h["cls"]), int(h["tonnage"]),
		fit.mounts_fitted(), fit.mounts().size()]
