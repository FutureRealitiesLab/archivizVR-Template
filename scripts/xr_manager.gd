## xr_manager.gd
## Autoload-Singleton: Verwaltet OpenXR-Initialisierung und FPV-Fallback.
##
## Szenenbaum-Integration:
##   - Als Autoload eingetragen: Project > Project Settings > Autoload
##   - Name: "XRManager"
##
## Verwendung in anderen Skripten:
##   XRManager.mode_changed.connect(_on_mode_changed)
##   if XRManager.is_vr_active(): ...

extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Wird nach Initialisierung ausgesendet. `success` = true wenn VR aktiv.
signal initialized(success: bool)

## Wird ausgesendet wenn der Modus wechselt (z.B. VR → FPV oder umgekehrt).
signal mode_changed(new_mode: Mode)

# ---------------------------------------------------------------------------
# Enumerationen & Konstanten
# ---------------------------------------------------------------------------

enum Mode {
	NONE,   ## Noch nicht initialisiert
	VR,     ## OpenXR aktiv
	FPV,    ## First-Person-View (Maus/Tastatur)
}

const VR_RENDER_SCALE: float = 1.0      ## 1.0 = nativ (Supersampling auf 1.2–1.4 für mehr Schärfe)
const FPV_RENDER_SCALE: float = 1.0     ## Desktop: 1.0 (native)
const VR_FOVEATION_LEVEL: int = 2       ## 0=none, 1=low, 2=medium, 3=high
const PHYSICS_FPS_VR: int = 90          ## VR benötigt stabile 90 Hz
const PHYSICS_FPS_FPV: int = 60

# ---------------------------------------------------------------------------
# Exported Variables
# ---------------------------------------------------------------------------

## Pfad zur VR-Player-Szene (mit XROrigin3D)
@export var vr_player_scene: PackedScene
## Pfad zur FPV-Player-Szene (mit CharacterBody3D + Camera3D)
@export var fpv_player_scene: PackedScene
## Node-Pfad im Szenenbaum wo der Player gespawnt wird
@export var player_spawn_parent_path: NodePath = NodePath("/root/Main/World")
## Spawn-Position für den Player
@export var spawn_position: Vector3 = Vector3(0.0, 1.7, 5.0)

# ---------------------------------------------------------------------------
# Private Variablen
# ---------------------------------------------------------------------------

var _current_mode: Mode = Mode.NONE
var _openxr_interface: OpenXRInterface = null
var _player_instance: Node3D = null
var _initialized: bool = false

# ---------------------------------------------------------------------------
# Godot Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# OpenXR-Interface Signals verbinden (falls die Extension geladen ist)
	if OpenXRInterface:
		pass  # Verbindungen werden in initialize() gesetzt

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown_xr()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Hauptmethode: Initialisiert VR oder fällt auf FPV zurück.
## Wird aus dem Main-Skript nach _ready() aufgerufen.
func initialize() -> void:
	if _initialized:
		push_warning("XRManager: Bereits initialisiert – initialize() ignoriert.")
		return

	print("XRManager: Starte Initialisierung...")

	if _try_initialize_openxr():
		_activate_vr_mode()
	else:
		_activate_fpv_mode()

	_initialized = true


## Gibt den aktuell aktiven Modus zurück.
func get_mode() -> Mode:
	return _current_mode


## Gibt true zurück wenn VR aktiv ist.
func is_vr_active() -> bool:
	return _current_mode == Mode.VR


## Gibt die aktive Player-Node zurück (XROrigin3D oder CharacterBody3D).
func get_player() -> Node3D:
	return _player_instance


## Gibt die aktive Kamera zurück (XRCamera3D oder Camera3D).
func get_camera() -> Camera3D:
	if _player_instance == null:
		return null
	# Suche in der Player-Szene nach der Kamera
	return _player_instance.find_child("*Camera*", true, false) as Camera3D


## Ermöglicht manuelles Umschalten in FPV (z.B. für Editor-Tests ohne HMD).
func force_fpv_mode() -> void:
	if _current_mode == Mode.FPV:
		return
	_shutdown_xr()
	_activate_fpv_mode()


## Setzt die Render-Skala dynamisch (Performance-Tuning zur Laufzeit).
func set_render_scale(scale: float) -> void:
	scale = clampf(scale, 0.5, 2.0)
	get_viewport().scaling_3d_scale = scale
	print("XRManager: Render-Skala gesetzt auf %.2f" % scale)

# ---------------------------------------------------------------------------
# Private Initialisierungs-Logik
# ---------------------------------------------------------------------------

func _try_initialize_openxr() -> bool:
	# 1. Interface suchen
	_openxr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if _openxr_interface == null:
		push_warning("XRManager: OpenXR-Interface nicht gefunden. " +
				"Ist das Plugin/der Treiber installiert? Wechsle zu FPV.")
		return false

	# 2. Interface initialisieren – nur wenn noch nicht geschehen.
	# Godot initialisiert OpenXR automatisch wenn openxr/enabled=true gesetzt ist.
	# Ein zweiter initialize()-Aufruf gibt false zurück und würde FPV-Fallback auslösen.
	if not _openxr_interface.is_initialized():
		if not _openxr_interface.initialize():
			push_warning("XRManager: OpenXR.initialize() fehlgeschlagen. " +
					"Kein HMD erkannt oder Laufzeit nicht aktiv. Wechsle zu FPV.")
			_openxr_interface = null
			return false

	# 3. Signals verbinden
	if not _openxr_interface.session_begun.is_connected(_on_openxr_session_begun):
		_openxr_interface.session_begun.connect(_on_openxr_session_begun)
	if not _openxr_interface.session_stopping.is_connected(_on_openxr_session_stopping):
		_openxr_interface.session_stopping.connect(_on_openxr_session_stopping)
	if not _openxr_interface.session_focussed.is_connected(_on_openxr_session_focussed):
		_openxr_interface.session_focussed.connect(_on_openxr_session_focussed)

	print("XRManager: OpenXR Interface bereit (is_initialized=%s)." % _openxr_interface.is_initialized())
	return true


func _activate_vr_mode() -> void:
	print("XRManager: Aktiviere VR-Modus.")

	# Viewport auf XR umstellen
	get_viewport().use_xr = true

	# Rendering-Optimierungen für VR
	_configure_rendering_for_vr()

	# VR-Player spawnen
	_spawn_player(true)

	_current_mode = Mode.VR
	mode_changed.emit(Mode.VR)
	initialized.emit(true)


func _activate_fpv_mode() -> void:
	print("XRManager: Aktiviere FPV-Modus.")

	# Sicherstellen dass kein XR-Viewport aktiv ist
	get_viewport().use_xr = false

	# Rendering-Optimierungen für Desktop
	_configure_rendering_for_fpv()

	# FPV-Player spawnen
	_spawn_player(false)

	# Maus fangen für FPV
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	_current_mode = Mode.FPV
	mode_changed.emit(Mode.FPV)
	initialized.emit(false)


func _spawn_player(is_vr: bool) -> void:
	# Alten Player entfernen falls vorhanden
	if _player_instance != null and is_instance_valid(_player_instance):
		_player_instance.queue_free()
		_player_instance = null

	# Szene bestimmen
	var scene_to_load: PackedScene = vr_player_scene if is_vr else fpv_player_scene

	if scene_to_load == null:
		push_error("XRManager: Player-Szene ist nicht zugewiesen! " +
				"Bitte '%s' im Inspector setzen." % ("vr_player_scene" if is_vr else "fpv_player_scene"))
		return

	# Instanzieren
	_player_instance = scene_to_load.instantiate() as Node3D

	# Parent-Node finden
	var parent: Node = get_node_or_null(player_spawn_parent_path)
	if parent == null:
		push_warning("XRManager: spawn_parent_path '%s' nicht gefunden, " +
				"verwende /root." % player_spawn_parent_path)
		parent = get_tree().root

	parent.add_child(_player_instance)
	_player_instance.global_position = spawn_position

	# Kamera erzwingen (hilft gegen Grey Screen)
	var cam = get_camera()
	if cam:
		cam.make_current()
		print("XRManager: Kamera '%s' als aktiv gesetzt." % cam.name)

	print("XRManager: %s-Player gespawnt bei %s (Parent: %s)" % [
		"VR" if is_vr else "FPV", spawn_position, parent.get_path()
	])

# ---------------------------------------------------------------------------
# Rendering-Konfiguration
# ---------------------------------------------------------------------------

func _configure_rendering_for_vr() -> void:
	var vp: Viewport = get_viewport()

	# Render-Skala: 1.0 nativ (Quest 2 hat ~1832x1920 pro Auge – bereits sehr hoch)
	# Für Supersampling auf 1.2 erhöhen, wenn Framerate es erlaubt.
	vp.scaling_3d_scale = VR_RENDER_SCALE
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

	# MSAA 4x – in gl_compatibility problemlos, kein Subpass-Konflikt
	# TAA in VR deaktivieren (erzeugt Ghosting bei Kopfbewegung)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_taa = false
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

	# Foveated Rendering über project.godot (openxr/foveation_level=2) geregelt.
	# VRS_XR NICHT setzen – kollidiert mit der Meta-eigenen FFR-Extension.
	vp.vrs_mode = Viewport.VRS_DISABLED

	# Physics für 90Hz
	Engine.physics_ticks_per_second = PHYSICS_FPS_VR

	# Umgebungsqualität für gl_compatibility:
	# SDFGI/SSAO/SSIL/SSR sind in gl_compatibility nicht verfügbar → deaktivieren.
	# Tonemapping und Glow funktionieren und verbessern die Bildqualität deutlich.
	var world_env: WorldEnvironment = _find_world_environment()
	if world_env and world_env.environment:
		var env: Environment = world_env.environment
		env.sdfgi_enabled = false   # Nicht in gl_compatibility
		env.ssao_enabled = false    # Nicht in gl_compatibility
		env.ssil_enabled = false    # Nicht in gl_compatibility
		env.ssr_enabled = false     # Nicht in gl_compatibility
		# Filmic Tonemapping: warme, filmische Wirkung – ideal für Architekturviz
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.0
		env.tonemap_white = 6.0
		# Glow: subtiler Bloom-Effekt für Lichter und helle Flächen
		env.glow_enabled = true
		env.glow_normalized = true
		env.glow_intensity = 0.4
		env.glow_bloom = 0.05
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	print("XRManager: VR-Rendering konfiguriert (gl_compatibility, MSAA 4x, Filmic Tonemapping, Glow).")


func _configure_rendering_for_fpv() -> void:
	var vp: Viewport = get_viewport()

	# Native Auflösung für Desktop
	vp.scaling_3d_scale = FPV_RENDER_SCALE
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

	# TAA für Desktop (glatte Kanten ohne Performance-Kosten)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_taa = true
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA

	# Physics für 60Hz
	Engine.physics_ticks_per_second = PHYSICS_FPS_FPV

	# Umgebungs-GI: SDFGI für hohe Qualität aktivieren
	var world_env: WorldEnvironment = _find_world_environment()
	if world_env and world_env.environment:
		var env: Environment = world_env.environment
		env.sdfgi_enabled = true
		env.ssao_enabled = true
		env.ssil_enabled = false  # SSIL ist sehr teuer, optional
		env.ssr_enabled = true    # Screen-Space Reflexionen für Glas/Böden

	print("XRManager: Desktop/FPV-Rendering konfiguriert (TAA, SSAO, SDFGI).")


func _find_world_environment() -> WorldEnvironment:
	# Suche rekursiv nach WorldEnvironment in der Szene
	return _find_node_of_type(get_tree().current_scene, "WorldEnvironment") as WorldEnvironment


func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node == null: return null
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result: Node = _find_node_of_type(child, type_name)
		if result != null:
			return result
	return null

# ---------------------------------------------------------------------------
# Shutdown
# ---------------------------------------------------------------------------

func _shutdown_xr() -> void:
	if _openxr_interface != null:
		# Signals trennen
		if _openxr_interface.session_begun.is_connected(_on_openxr_session_begun):
			_openxr_interface.session_begun.disconnect(_on_openxr_session_begun)
		if _openxr_interface.session_stopping.is_connected(_on_openxr_session_stopping):
			_openxr_interface.session_stopping.disconnect(_on_openxr_session_stopping)
		_openxr_interface = null

	get_viewport().use_xr = false

# ---------------------------------------------------------------------------
# OpenXR Signal-Handler
# ---------------------------------------------------------------------------

func _on_openxr_session_begun() -> void:
	print("XRManager: OpenXR Session gestartet.")
	# Refresh-Rate erst setzen wenn Session aktiv ist, nicht schon beim initialize()
	if _openxr_interface:
		_openxr_interface.display_refresh_rate = 90.0
		print("XRManager: 90Hz Refresh-Rate gesetzt.")

func _on_openxr_session_stopping() -> void:
	print("XRManager: OpenXR Session gestoppt – wechsle zu FPV.")
	# HMD wurde abgesetzt oder Verbindung getrennt → FPV als Fallback
	call_deferred("force_fpv_mode")

func _on_openxr_session_focussed() -> void:
	print("XRManager: OpenXR Session fokussiert (Rendering aktiv).")
