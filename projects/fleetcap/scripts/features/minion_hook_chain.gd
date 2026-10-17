class_name MinionHookChain
extends RefCounted
## WHAT THIS IS: a small helper of the council branch. Combat has ONE
## minion_scale_hook (how hard a minion hits one target), and four forks'
## feature modules set it: MinionCapFeature (minion_cap), MoraleFeature
## (morale), MinionBuffs (salvage_core, epic, feats) and BreachFeature
## (breach:fulldmg). Alone, each simply set the hook; together, the last one
## would silently switch the others off. add() lets them share it.
##
## HOW IT WORKS: add(world, hook, run_last):
##   1. Combat has no hook yet: the new hook becomes THE hook, exactly what
##      the feature did in its own fork (so one feature alone plays as it
##      did there).
##   2. Combat already has a hook: a chain is made (once) that holds the old
##      hook, and the new one is added to it. The chain asks every hook in
##      turn; each gets the strength the hook before it gave back. Hooks
##      added with run_last = true (the cap of minion_cap) are asked after
##      all others, so a cap stays a cap whatever else is on.
## BreachFeature keeps its own way of sharing (it remembers the hook it found
## and asks it), so it works with or without a chain.
## The chain is kept alive in a World meta value (a Callable alone does not
## keep its object alive).
##
## WHO USES IT: MinionCapFeature, MoraleFeature and MinionBuffs call add().
## Combat._rescale_minion_hit() calls the hook as before.

## Name of the World meta value that keeps the chain alive.
const META := "minion_hook_chain"

## The hooks asked first, in the order they were added.
var hooks: Array[Callable] = []
## The hooks asked last (caps), in the order they were added.
var last_hooks: Array[Callable] = []


## Give Combat's minion_scale_hook one more user (see HOW IT WORKS).
## `hook` takes (minion, target, strength) and returns the strength to use;
## `run_last` = true puts it after every other hook.
static func add(w: World, hook: Callable, run_last: bool = false) -> void:
	# Step 1: nobody uses the hook yet: take it, as the feature did alone.
	var cur: Callable = w.combat.minion_scale_hook
	if not cur.is_valid():
		w.combat.minion_scale_hook = hook
		return
	# Step 2: find the chain, or make it around the hook that is there.
	var chain: MinionHookChain = null
	if cur.get_object() is MinionHookChain:
		chain = cur.get_object() as MinionHookChain
	else:
		chain = MinionHookChain.new()
		if _is_last(w, cur):
			chain.last_hooks.append(cur)
		else:
			chain.hooks.append(cur)
		w.set_meta(META, chain)
		w.combat.minion_scale_hook = Callable(chain, "_call")
	# Step 3: add the new hook to its group.
	if run_last:
		chain.last_hooks.append(hook)
	else:
		chain.hooks.append(hook)


## Was the hook `h` that is already set added as a "last" hook? (Only the
## minion_cap hook is; it is recognised by its method name on a
## MinionCapFeature.)
static func _is_last(_w: World, h: Callable) -> bool:
	return h.get_object() is MinionCapFeature


## The chained hook Combat calls: every hook in turn, then the caps.
func _call(m: Minion, target: Unit, scale: float) -> float:
	var s := scale
	for h: Callable in hooks:
		s = float(h.call(m, target, s))
	for h: Callable in last_hooks:
		s = float(h.call(m, target, s))
	return s
