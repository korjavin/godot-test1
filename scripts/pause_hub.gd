class_name PauseHub
extends Object
## ============================================================================
## PAUSE HUB — the one place in this project that writes `get_tree().paused`
## ============================================================================
##
## Seven scripts freeze the world: `pause_controller.gd` (P), `help_overlay.gd`
## (?), `skill_tree_ui.gd` (K), `mp_ui.gd` (the MP panel), `start_overlay.gd`
## (the start menu and the intro film), `mobile_input.gd` (focus loss / portrait)
## and `landmark_toast.gd` (a pending quiz). Before this file each one owned the
## pause outright and carried the same guard:
##
##     if not tree.paused:          # take
##         tree.paused = true
##         _paused_by_us = true
##     ...
##     if _paused_by_us:            # release
##         _paused_by_us = false
##         tree.paused = false
##
## Every one of those seven was individually correct and the SYSTEM was still
## broken, because the discipline was FIRST-TAKER-OWNS rather than a refcount: an
## overlay opening over an already-paused tree claimed nothing, so whichever
## owner released first started the world under every overlay still on screen.
## Reproducible on the shipped game with no exotic setup: P to pause, `?` to open
## the keymap card over it (that overlay is PROCESS_MODE_ALWAYS and opening over
## a pause is the point of it), P again — and the crocodiles walk about behind
## the help card. `landmark_toast`'s quiz made it reachable unattended, because
## its release arrives on QUIZ_TIMEOUT rather than on a keypress.
##
## So: HOLDERS, COUNTED BY IDENTITY. `take(who)` adds a holder, `release(who)`
## removes one, and the tree is paused exactly while the holder set is non-empty.
## Both operations end in the same one line — `tree.paused = not
## _holders.is_empty()` — which is what makes the invariant impossible to get
## half-right at a call site.
##
## WHAT THIS FILE DELIBERATELY DOES NOT OWN:
##
##  * **Policy.** `pause_controller` and `mobile_input` refuse to pause over Game
##    Over; `landmark_toast` refuses in a multiplayer room; `skill_tree_ui`
##    refuses to OPEN under somebody else's pause. Those are decisions about the
##    feature, not about the mechanism, and they stay with the feature. This file
##    would have to know about game-over state, rooms and draw order to hold them,
##    and would then be the thing every future pauser has to edit.
##  * **The caller's own bit.** Each script keeps its `_paused_by_us` /
##    `paused_by_driver` flag. It no longer means "we hold THE pause" — it means
##    "we hold A claim", which is the only thing a caller can honestly know — and
##    it is still what decides whether a release is ours to make and whether an
##    input under a pause is ours to answer.
##  * **Reading the pause as a CONDITION.** `touch_controls`' portrait guard and
##    motion watch, `skill_tree_ui`'s refusal to open, `landmark_toast`'s digit
##    guard and `_take_pause` all ask "is the world stopped?", which is
##    `get_tree().paused` and nothing to do with who stopped it. They are NOT
##    routed through here, on purpose.
##
## STATIC, NOT AN AUTOLOAD. This project has no autoloads at all — `Progression`,
## `BestRunStore`, `ToonShading` and `MobileSensors` are all static-helper classes
## for the same reason: a scene run standalone (or a headless self-check driving a
## hand-built fixture) gets the mechanism for free, with no `project.godot` edit
## and nothing to forget to register.
##
## Covered by `scripts/pause_selfcheck.gd`, which drives the overlapping-holders
## lifecycle both through this class directly and through the real
## `pause_controller` / `help_overlay` nodes that the bug was reported against.

## Instance ids of everything currently holding the pause. Ids and not the objects
## themselves so a holder freed without releasing (a scene change, a self-check
## tearing its fixture down) can be detected and dropped rather than resurrecting
## a dangling reference — see `_prune()`.
static var _holders: Dictionary = {}


static func take(who: Node) -> void:
	"""
	Claim the pause for `who`. Idempotent: a second claim by the same holder is
	the same one claim, so a caller that re-asserts every frame (`mp_ui` and
	`start_overlay` both do, deliberately) costs one dictionary write and changes
	nothing.
	"""
	if who == null:
		return
	_holders[who.get_instance_id()] = true
	_apply(who.get_tree())


static func release(who: Node) -> void:
	"""
	Drop `who`'s claim. The world starts again only if that was the last one — the
	whole point of this file. Releasing without holding is a no-op, so the callers'
	`if _paused_by_us` guards stay belt-and-braces rather than load-bearing.
	"""
	if who == null:
		return
	_holders.erase(who.get_instance_id())
	# `get_tree()` is still valid inside `_exit_tree` (which is where
	# `landmark_toast` releases a question that outlived its scene), but a node
	# already fully out of the tree answers null. Dropping the claim is the half
	# that matters; the next take/release applies it.
	_apply(who.get_tree())


static func holder_count() -> int:
	"""How many live holders there are. For self-checks and debug surfaces."""
	_prune()
	return _holders.size()


static func _apply(tree: SceneTree) -> void:
	"""THE INVARIANT, in one line, reached from both take and release."""
	_prune()
	if tree == null:
		return
	tree.paused = not _holders.is_empty()


static func _prune() -> void:
	"""
	Forget holders that no longer exist. Without this a holder freed mid-claim
	would pin the tree paused forever with nothing alive that could release it —
	the softlock this whole mechanism is supposed to make impossible.

	ponytail: pruning happens on take/release/holder_count and nowhere else,
	because this class has no tick of its own. So the last holder being FREED
	rather than releasing leaves the tree paused until somebody next touches the
	hub — exactly as bad as the pre-refcount behaviour was, and no worse. The
	upgrade path if that ever bites is an `_exit_tree` release in the holder (the
	shape `landmark_toast` already uses), not a timer in here.
	"""
	for id: int in _holders.keys():
		if not is_instance_id_valid(id):
			_holders.erase(id)
