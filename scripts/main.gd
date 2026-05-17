## main.gd
## Haupt-Skript: Orchestriert Spielstart, XR-Initialisierung und Szenenlogik.
## Attach an den Root-Node der main.tscn.

extends Node

# ---------------------------------------------------------------------------
# Export-Variablen
# ---------------------------------------------------------------------------

@export var startup_scene: String = "res://scenes/environment/demo_room.tscn"

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	print("Main: Starte ArchViz VR...")

	# XR-Manager-Signals verbinden (Autoload)
	XRManager.initialized.connect(_on_xr_initialized)
	XRManager.mode_changed.connect(_on_mode_changed)

	# Spieler-Szenen dem XRManager zuweisen
	XRManager.vr_player_scene = load("res://scenes/player/xr_player.tscn")
	XRManager.fpv_player_scene = load("res://scenes/player/fpv_player.tscn")
	XRManager.player_spawn_parent_path = NodePath("/root/Main")
	XRManager.spawn_position = Vector3(0.0, 0.1, 5.0)

	# Startszene laden
	SceneManager.load_scene(startup_scene, false)
	await SceneManager.scene_loaded

	# XR initialisieren (spawnt Player automatisch)
	XRManager.initialize()

	print("Main: Initialisierung abgeschlossen.")


func _input(event: InputEvent) -> void:
	# Globale Shortcuts
	if event.is_action_pressed("ui_cancel") and not XRManager.is_vr_active():
		# FPV: Escape-Taste für Maus-Freigabe (wird im FPVController gehandelt)
		pass

	# Debug: F1 = Force FPV (nützlich für Tests ohne HMD)
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_F1:
		if (event as InputEventKey).pressed:
			XRManager.force_fpv_mode()
			print("Main: FPV-Modus erzwungen (F1).")

	# Debug: F2 = Performance-Info
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_F2:
		if (event as InputEventKey).pressed:
			_print_performance_info()

# ---------------------------------------------------------------------------
# Signal-Handler
# ---------------------------------------------------------------------------

func _on_xr_initialized(success: bool) -> void:
	if success:
		print("Main: VR-Modus aktiv. HMD erkannt und initialisiert.")
	else:
		print("Main: FPV-Modus aktiv. Kein HMD erkannt oder VR nicht verfügbar.")


func _on_mode_changed(new_mode: XRManager.Mode) -> void:
	print("Main: Modus gewechselt → %s" % XRManager.Mode.keys()[new_mode])

# ---------------------------------------------------------------------------
# Hilfsmethoden
# ---------------------------------------------------------------------------

func _print_performance_info() -> void:
	print("=== Performance Info ===")
	print("FPS: %d" % Engine.get_frames_per_second())
	print("Draw Calls: %d" % RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("Vertices: %d" % RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("Video RAM: %.1f MB" % (
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
			/ (1024.0 * 1024.0)))
	print("Modus: %s" % XRManager.get_mode())
	print("========================")
