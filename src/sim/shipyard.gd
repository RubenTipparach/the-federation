class_name Shipyard
extends RefCounted

## The refit transaction: shop, ship, and cargo, with nothing charged until it
## is confirmed. This owns every rule in docs/10-shipyard.md, and the screen
## owns none of them (CLAUDE.md 4.1 and 5.2). No Node dependencies, so the
## whole thing is exercised headless before it is ever drawn.
##
## An item is a Dictionary: { uid, weapon_id, owned, condition }.
## owned is true when the captain already had it on entry, which is what makes
## the same drag free in one direction and a purchase in the other.
## condition is the fraction of the item's boxes remaining, 1.0 for fresh gear.

const SHOP: String = "shop"
const CARGO: String = "cargo"

var fit: ShipFit
var cargo: Array[Dictionary] = []
var shop: Array[Dictionary] = []
var credits: int = 0

var _next_uid: int = 0


static func create(p_fit: ShipFit, p_credits: int, shop_ids: Array,
		cargo_ids: Array = []) -> Shipyard:
	var y: Shipyard = Shipyard.new()
	y.fit = p_fit.duplicate_fit()
	y.credits = p_credits
	for id in shop_ids:
		y.shop.append(y._make(String(id), false))
	for id in cargo_ids:
		y.cargo.append(y._make(String(id), true))
	return y


func _make(weapon_id: String, owned: bool, condition: float = 1.0) -> Dictionary:
	_next_uid += 1
	return {
		"uid": "i%d" % _next_uid,
		"weapon_id": weapon_id,
		"owned": owned,
		"condition": clampf(condition, 0.0, 1.0),
	}


# ---- prices ------------------------------------------------------------------

func list_price(item: Dictionary) -> int:
	return int(Catalog.weapon(String(item["weapon_id"]))["price"])


## What the yard pays. The spread is its margin, and damaged gear is worth its
## remaining fraction, so a shot up phaser cannot be flipped for full value.
func sale_price(item: Dictionary) -> int:
	var frac: float = float(Catalog.tuning()["shipyard"]["sell_back_frac"])
	return int(round(float(list_price(item)) * frac * float(item["condition"])))


func item_space(item: Dictionary) -> int:
	return int(Catalog.weapon(String(item["weapon_id"]))["costs"]["space"])


# ---- where things are --------------------------------------------------------

func find(uid: String) -> Dictionary:
	for i in range(shop.size()):
		if String(shop[i]["uid"]) == uid:
			return { "item": shop[i], "zone": SHOP, "index": i }
	for i in range(cargo.size()):
		if String(cargo[i]["uid"]) == uid:
			return { "item": cargo[i], "zone": CARGO, "index": i }
	for mount_id in fit.slots.keys():
		var fitted: Dictionary = _fitted.get(String(mount_id), {})
		if not fitted.is_empty() and String(fitted["uid"]) == uid:
			return { "item": fitted, "zone": "mount", "mount": String(mount_id) }
	return {}


## Items fitted to mounts, keyed by mount id. The fit itself only knows weapon
## ids, so the yard tracks which physical item is in each mount, and that is
## what carries condition and ownership through the transaction.
var _fitted: Dictionary = {}


## Put the ship's current loadout into the transaction as owned items.
func adopt_fit() -> void:
	_fitted = {}
	for mount in fit.mounts():
		var mount_id: String = String(mount["id"])
		var weapon_id: String = String(fit.slots.get(mount_id, ""))
		if not weapon_id.is_empty():
			_fitted[mount_id] = _make(weapon_id, true)


func fitted_in(mount_id: String) -> Dictionary:
	return _fitted.get(mount_id, {})


func cargo_used() -> int:
	var n: int = 0
	for item in cargo:
		n += item_space(item)
	return n


func cargo_capacity() -> int:
	return int(fit.hull().get("cargo_space", 0))


# ---- moves -------------------------------------------------------------------

## Move one item to the shop, to cargo, or to a mount. Returns a result with
## ok and a reason, so the screen can say why rather than swallowing the drag.
func move(uid: String, to_zone: String, mount_id: String = "") -> Dictionary:
	var src: Dictionary = find(uid)
	if src.is_empty():
		return { "ok": false, "reason": "no such item" }
	var item: Dictionary = src["item"]

	if to_zone == "mount":
		if not fit.is_legal(_mount(mount_id), Catalog.weapon(String(item["weapon_id"]))):
			return { "ok": false, "reason": "%s does not accept that weapon" % mount_id }
		if String(src.get("zone", "")) == "mount" and String(src["mount"]) == mount_id:
			return { "ok": false, "reason": "already there" }

	_lift(src)

	# A weapon already in the target mount is unshipped rather than destroyed.
	if to_zone == "mount" and not fitted_in(mount_id).is_empty():
		var displaced: Dictionary = _fitted[mount_id]
		cargo.append(displaced)
		_fitted.erase(mount_id)

	match to_zone:
		SHOP:
			shop.append(item)
		CARGO:
			cargo.append(item)
		"mount":
			_fitted[mount_id] = item
			fit.slots[mount_id] = String(item["weapon_id"])
	return { "ok": true, "reason": "moved" }


func _lift(src: Dictionary) -> void:
	match String(src["zone"]):
		SHOP:
			shop.remove_at(int(src["index"]))
		CARGO:
			cargo.remove_at(int(src["index"]))
		"mount":
			var mount_id: String = String(src["mount"])
			_fitted.erase(mount_id)
			fit.slots[mount_id] = ""


func _mount(mount_id: String) -> Dictionary:
	for m in fit.mounts():
		if String(m["id"]) == mount_id:
			return m
	return {}


# ---- the tally ---------------------------------------------------------------

## Purchases are items the captain now holds that the shop owned on entry.
## Sales are the reverse. Ownership decides, which is exactly why moving your
## own gear between the hold and a mount costs nothing.
func tally() -> Dictionary:
	var purchases: int = 0
	var sales: int = 0
	for item in _mine():
		if not bool(item["owned"]):
			purchases += list_price(item)
	for item in shop:
		if bool(item["owned"]):
			sales += sale_price(item)
	return {
		"purchases": purchases,
		"sales": sales,
		"balance": sales - purchases,
		"credits_after": credits + sales - purchases,
	}


func _mine() -> Array[Dictionary]:
	var out: Array[Dictionary] = cargo.duplicate()
	for mount_id in _fitted.keys():
		out.append(_fitted[mount_id])
	return out


# ---- confirming --------------------------------------------------------------

## Everything standing between the captain and a settled transaction, in the
## order docs/10 section 4 lists them. An empty array means Confirm is allowed.
func blockers() -> Array[String]:
	var out: Array[String] = []
	var over: int = cargo_used() - cargo_capacity()
	if over > 0:
		out.append("Cargo hold is over capacity by %d space." % over)
	var t: Dictionary = tally()
	if int(t["credits_after"]) < 0:
		out.append("Short %d credits to settle the balance." % [-int(t["credits_after"])])
	for mount in fit.mounts():
		var mount_id: String = String(mount["id"])
		var item: Dictionary = fitted_in(mount_id)
		if not item.is_empty() and not fit.is_legal(mount, Catalog.weapon(String(item["weapon_id"]))):
			out.append("%s cannot be fitted to %s." % [
				String(Catalog.weapon(String(item["weapon_id"]))["name"]), mount_id])
	return out


func is_empty_transaction() -> bool:
	var t: Dictionary = tally()
	return int(t["purchases"]) == 0 and int(t["sales"]) == 0


func can_confirm() -> bool:
	return blockers().is_empty() and not is_empty_transaction()


## Settle: money moves once, and everything the captain now holds becomes
## theirs. Returns the new credit balance, or the old one if it was refused.
func confirm() -> int:
	if not can_confirm():
		return credits
	var t: Dictionary = tally()
	credits = int(t["credits_after"])
	for item in _mine():
		item["owned"] = true
	for item in shop:
		item["owned"] = false
	return credits
