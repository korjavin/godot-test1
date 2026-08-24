extends SceneTree
## Is a working WebRTC implementation actually available to this build?
##
## Run it headless, from the project root:
##
##     godot --headless --path . --script res://scripts/webrtc_addon_check.gd
##
## Prints "WEBRTC OK" and quits 0, or prints why it is missing and quits 1.
##
## This is the check behind `./fetch_webrtc_addon.sh` — the one thing that fails
## if the addon is absent, half-extracted, or in the wrong directory. It is
## deliberately NOT part of `mp_selfcheck.gd`: that one must stay green on CI and
## on the web export, where no addon exists and none is wanted (browsers bring
## their own WebRTC). This one is the opposite — it exists to fail loudly on a
## desktop machine that has not run the fetch script.
##
## Nothing here touches the network: opening a `WebRTCPeerConnection` and asking
## it for a data channel is entirely local setup. No ICE gathering is started,
## no STUN server is contacted, no socket is opened.

const MPManager: GDScript = preload("res://scripts/mp_manager.gd")


func _initialize() -> void:
	var failure: String = _run_check()
	if failure.is_empty():
		print("WEBRTC OK")
		quit(0)
	else:
		printerr("WEBRTC MISSING: " + failure)
		printerr("Run ./fetch_webrtc_addon.sh from the project root — see README.")
		quit(1)


func _run_check() -> String:
	"""Returns "" when WebRTC works here, else why it does not."""

	# 0. A GDScript runtime error unwinds the erroring function and hands the
	#    caller the return type's DEFAULT — "" here, which `_initialize` reads as
	#    success. So a `mp_manager.gd` that failed to compile would print
	#    "WEBRTC OK". It fails to compile when the project has never been
	#    imported (its `class_name` dependencies are not in the global class
	#    cache yet), which is exactly the state of a fresh clone. Hence this
	#    guard: check the method is *there* before trusting what it returns.
	if not MPManager.has_method("webrtc_available"):
		return "mp_manager.gd did not compile — run `godot --headless --path . --import` first"

	# 1. The probe the game itself uses. If this disagrees with the rest of the
	#    check, the addon is installed somewhere `MPManager` will never look, and
	#    the MP panel would report "unavailable" beside a perfectly good library.
	if not MPManager.webrtc_available():
		return "MPManager.webrtc_available() is false — nothing at %s" % \
			MPManager.WEBRTC_ADDON_PATH

	# 2. Godot ships the *class* on every platform; only the implementation is
	#    missing. So a null instance — not an unknown class — is what "no
	#    extension configured" looks like from GDScript.
	var conn: WebRTCPeerConnection = WebRTCPeerConnection.new()
	if conn == null:
		return "WebRTCPeerConnection.new() returned null — no WebRTC extension is registered"

	# 3. `initialize()` is where a stub would give up. Empty config on purpose:
	#    no ICE servers means no STUN traffic, and this check stays offline.
	var err: int = conn.initialize({})
	if err != OK:
		return "WebRTCPeerConnection.initialize() failed with error %d" % err

	# 4. The mesh is built out of data channels (see `MPManager._open_connection`),
	#    so a connection that cannot make one is no use to this game even if the
	#    two steps above passed.
	var channel: WebRTCDataChannel = conn.create_data_channel("selfcheck", {"id": 1, "negotiated": true})
	if channel == null:
		return "create_data_channel() returned null — the extension loaded but is not functional"

	conn.close()
	return ""
