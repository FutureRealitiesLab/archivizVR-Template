## vr_test.gd
## Minimales Initialisierungsskript für die VR-Testszene.
## Initialisiert OpenXR direkt, ohne XRManager.

extends Node3D

func _ready() -> void:
	print("VRTest: Starte VR-Testszene...")

	var xr_interface := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null:
		push_error("VRTest: OpenXR Interface nicht gefunden! Kein HMD angeschlossen?")
		return

	print("VRTest: OpenXR gefunden, is_initialized = %s" % xr_interface.is_initialized())

	if not xr_interface.is_initialized():
		if not xr_interface.initialize():
			push_error("VRTest: OpenXR.initialize() fehlgeschlagen!")
			return
		print("VRTest: OpenXR manuell initialisiert.")

	get_viewport().use_xr = true
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	print("VRTest: use_xr = true, MSAA deaktiviert.")

	# Refresh-Rate setzen sobald Session aktiv
	if not xr_interface.session_begun.is_connected(_on_session_begun):
		xr_interface.session_begun.connect(_on_session_begun)

	print("VRTest: Bereit. Warte auf OpenXR Session...")


func _on_session_begun() -> void:
	print("VRTest: OpenXR Session gestartet – Rendering aktiv!")
	var xr_interface := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface:
		xr_interface.display_refresh_rate = 90.0
		print("VRTest: 90Hz gesetzt.")
