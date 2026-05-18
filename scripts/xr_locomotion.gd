## xr_locomotion.gd
## VR-Fortbewegungs-Controller für den XROrigin3D.
## Unterstützt Smooth Locomotion und Teleport (Archivz-typisch).
##
## Szenenbaum:
##   XRPlayer (XROrigin3D) ← xr_manager.gd und dieses Skript
##   ├── XRCamera3D
##   ├── LeftController (XRController3D)
##   │   └── LeftHandMesh
##   └── RightController (XRController3D)
##       ├── RightHandMesh
##       └── TeleportRay (RayCast3D)
##
## Etagen-Navigation:
##   Gravity (Standard): Floor-Snap per Raycast von HMD-Position (X/Z) nach unten.
##   Funktioniert für Continuous Move und LBE, da der Raycast die echte
##   HMD-Horizontalposition nutzt – nicht den XROrigin-Mittelpunkt.
##   Collider für Nav-Ebenen/Rampen → Collision Layer 2 (floor_collision_mask).
##
##   Fly-Modus: Y-Taste = hoch, X-Taste = runter. Gravity dabei deaktiviert.
##   B-Taste → Gravity wieder aktivieren.

extends XROrigin3D

# ---------------------------------------------------------------------------
# Enumerationen
# ---------------------------------------------------------------------------

enum LocomotionMode {
	SMOOTH,     ## Smooth Locomotion (Thumbstick)
	TELEPORT,   ## Zeigen + Bestätigen
}

# ---------------------------------------------------------------------------
# Export-Variablen
# ---------------------------------------------------------------------------

@export_group("Locomotion")
@export var locomotion_mode: LocomotionMode = LocomotionMode.TELEPORT
@export var smooth_speed: float = 2.5          ## m/s Smooth Locomotion
@export var fly_speed: float = 2.0             ## m/s vertikale Bewegung im Fly-Modus
@export var smooth_turn_speed: float = 60.0    ## Grad/s sanfte Drehung
@export var snap_turn_angle: float = 30.0      ## Grad pro Snap-Turn
@export var snap_turn_cooldown: float = 0.3    ## Sekunden zwischen Snap-Turns

@export_group("Gravity / Floor Snap")
## Standard-Modus: Raycast vom HMD nach unten, XROrigin.y folgt dem Boden.
## Collision Layer für Nav-Ebenen und Rampen (Standard: Layer 2).
@export_flags_3d_physics var floor_collision_mask: int = 2
## Maximale Raycast-Distanz nach unten (m)
@export var floor_snap_distance: float = 10.0
## Wie schnell XROrigin.y dem Boden folgt (Lerp-Faktor)
@export var floor_snap_speed: float = 8.0
## Mindesthöhe über dem Boden ab der der Snap greift (vermeidet Zittern)
@export var floor_snap_threshold: float = 0.02

@export_group("Teleport")
@export var teleport_color_valid: Color = Color(0.2, 0.8, 0.2, 0.8)
@export var teleport_color_invalid: Color = Color(0.8, 0.2, 0.2, 0.8)
@export var max_teleport_distance: float = 15.0
@export var teleport_fade_duration: float = 0.15

@export_group("Komfort")
## Vignette bei Bewegung (reduziert Motion Sickness)
@export var comfort_vignette: bool = true
@export var comfort_vignette_strength: float = 0.4

# ---------------------------------------------------------------------------
# Node-Referenzen
# ---------------------------------------------------------------------------

@onready var xr_camera: XRCamera3D = $XRCamera3D
@onready var left_controller: XRController3D = $LeftController
@onready var right_controller: XRController3D = $RightController

# Optionale Teleport-Nodes (müssen in der Szene vorhanden sein)
var _teleport_ray: RayCast3D = null
var _teleport_marker: Node3D = null

# ---------------------------------------------------------------------------
# Private Variablen
# ---------------------------------------------------------------------------

var _snap_turn_cooldown_timer: float = 0.0
var _is_teleporting: bool = false
var _teleport_target: Vector3 = Vector3.ZERO
var _teleport_valid: bool = false

## Gravity-Modus: Floor-Snap via HMD-Raycast (Standard = true)
var gravity_enabled: bool = true
var fly_mode: bool = false
var _fly_up_pressed: bool = false
var _fly_down_pressed: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Controller Signals verbinden
	if left_controller:
		left_controller.button_pressed.connect(_on_left_button_pressed)
		left_controller.button_released.connect(_on_left_button_released)

	if right_controller:
		right_controller.button_pressed.connect(_on_right_button_pressed)
		right_controller.button_released.connect(_on_right_button_released)

	# Teleport-Ray suchen
	if right_controller:
		_teleport_ray = right_controller.find_child("TeleportRay", true, false) as RayCast3D
		_teleport_marker = get_tree().current_scene.find_child("TeleportMarker", true, false)

	print("XRLocomotion: Bereit. Modus: %s | Gravity: %s" % [
		LocomotionMode.keys()[locomotion_mode], gravity_enabled
	])

# ---------------------------------------------------------------------------
# Physics Process
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_snap_turn_cooldown_timer = maxf(0.0, _snap_turn_cooldown_timer - delta)

	match locomotion_mode:
		LocomotionMode.SMOOTH:
			_process_smooth_locomotion(delta)
		LocomotionMode.TELEPORT:
			_process_teleport_aim(delta)

	# Fly-Modus: vertikale Bewegung (deaktiviert Gravity)
	if fly_mode:
		if _fly_up_pressed:
			global_position.y += fly_speed * delta
		if _fly_down_pressed:
			global_position.y -= fly_speed * delta

	# Gravity: Floor-Snap via HMD-Raycast (nur wenn kein Fly-Modus)
	elif gravity_enabled:
		_process_floor_snap(delta)


func _process_smooth_locomotion(delta: float) -> void:
	if not left_controller or not left_controller.get_is_active():
		return

	# Bewegung: linker Thumbstick
	var move_axis: Vector2 = left_controller.get_vector2("primary")
	if move_axis.length() > 0.1:
		# Richtung relativ zur HMD-Blickrichtung (Yaw only)
		var cam_yaw: float = xr_camera.global_rotation.y
		var forward: Vector3 = Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
		var right: Vector3 = Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))

		var movement: Vector3 = (
			forward * (-move_axis.y) + right * move_axis.x
		) * smooth_speed * delta

		global_position += movement

	# Drehung: rechter Thumbstick (Smooth-Turn)
	if right_controller and right_controller.get_is_active():
		var turn_axis: Vector2 = right_controller.get_vector2("primary")
		if absf(turn_axis.x) > 0.1:
			rotate_y(deg_to_rad(-turn_axis.x * smooth_turn_speed * delta))


func _process_teleport_aim(_delta: float) -> void:
	if not _teleport_ray or not _is_teleporting:
		return

	# Teleport-Ziel aktualisieren
	if _teleport_ray.is_colliding():
		var hit_point: Vector3 = _teleport_ray.get_collision_point()
		var hit_normal: Vector3 = _teleport_ray.get_collision_normal()

		# Nur auf begehbaren Flächen teleportieren (Normale zeigt nach oben)
		_teleport_valid = hit_normal.dot(Vector3.UP) > 0.7 and \
				global_position.distance_to(hit_point) <= max_teleport_distance

		_teleport_target = hit_point

		if _teleport_marker:
			_teleport_marker.global_position = _teleport_target
			_teleport_marker.visible = _teleport_valid
	else:
		_teleport_valid = false
		if _teleport_marker:
			_teleport_marker.visible = false


## Floor-Snap: Raycast von HMD-Horizontalposition (X/Z) nach unten.
## Wichtig für LBE: Nicht vom XROrigin-Mittelpunkt, sondern von der echten
## HMD-Position – so folgt der Snap dem physisch stehenden Spieler.
func _process_floor_snap(delta: float) -> void:
	if not xr_camera:
		return

	var space_state := get_world_3d().direct_space_state

	# Raycast-Start: HMD X/Z, aber von etwas oberhalb des aktuellen Bodens
	var ray_start := Vector3(
		xr_camera.global_position.x,
		global_position.y + 2.0,
		xr_camera.global_position.z
	)
	var ray_end := ray_start + Vector3.DOWN * floor_snap_distance

	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = floor_collision_mask

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var floor_y: float = result.position.y
	var diff: float = floor_y - global_position.y

	# Nur anpassen wenn Abweichung über Threshold (verhindert Zittern)
	if absf(diff) > floor_snap_threshold:
		global_position.y = lerpf(global_position.y, floor_y, floor_snap_speed * delta)

# ---------------------------------------------------------------------------
# Button-Handler
# ---------------------------------------------------------------------------

func _on_right_button_pressed(button_name: String) -> void:
	match button_name:
		"trigger_click":
			if locomotion_mode == LocomotionMode.TELEPORT:
				_start_teleport_aim()
		"ax_button":
			# A-Taste: Locomotion-Modus wechseln
			_toggle_locomotion_mode()
		"by_button":
			# B-Taste: Gravity aktivieren (Fly-Modus beenden)
			_enable_gravity()


func _on_right_button_released(button_name: String) -> void:
	match button_name:
		"trigger_click":
			if locomotion_mode == LocomotionMode.TELEPORT and _is_teleporting:
				_execute_teleport()


func _on_left_button_pressed(button_name: String) -> void:
	match button_name:
		"by_button":
			# Y-Taste (oben): Hoch fliegen
			_enter_fly_mode()
			_fly_up_pressed = true
			print("XRLocomotion: Fly – Steigen")
		"ax_button":
			# X-Taste (unten): Runter fliegen
			_enter_fly_mode()
			_fly_down_pressed = true
			print("XRLocomotion: Fly – Sinken")
		"primary_click":
			# Linker Thumbstick-Klick: Gravity aktivieren
			_enable_gravity()


func _on_left_button_released(button_name: String) -> void:
	match button_name:
		"by_button":
			_fly_up_pressed = false
		"ax_button":
			_fly_down_pressed = false

# ---------------------------------------------------------------------------
# Teleport-Logik
# ---------------------------------------------------------------------------

func _start_teleport_aim() -> void:
	_is_teleporting = true
	if _teleport_ray:
		_teleport_ray.enabled = true
	print("XRLocomotion: Teleport-Ziel wählen...")


func _execute_teleport() -> void:
	_is_teleporting = false
	if _teleport_ray:
		_teleport_ray.enabled = false
	if _teleport_marker:
		_teleport_marker.visible = false

	if not _teleport_valid:
		return

	# Offset: XROrigin3D muss so positioniert werden, dass die Kamera
	# (HMD) am Zielpunkt landet, nicht der Origin
	var camera_offset: Vector3 = xr_camera.global_position - global_position
	camera_offset.y = 0.0  # Nur horizontalen Offset berücksichtigen

	global_position = _teleport_target - camera_offset
	global_position.y = _teleport_target.y  # Bodenniveau

	print("XRLocomotion: Teleportiert zu %s" % _teleport_target)

# ---------------------------------------------------------------------------
# Locomotion-Modi
# ---------------------------------------------------------------------------

func _toggle_locomotion_mode() -> void:
	if locomotion_mode == LocomotionMode.SMOOTH:
		locomotion_mode = LocomotionMode.TELEPORT
		print("XRLocomotion: Wechsel zu Teleport-Modus")
	else:
		locomotion_mode = LocomotionMode.SMOOTH
		print("XRLocomotion: Wechsel zu Smooth-Locomotion-Modus")


func _enter_fly_mode() -> void:
	fly_mode = true
	gravity_enabled = false


func _enable_gravity() -> void:
	fly_mode = false
	gravity_enabled = true
	_fly_up_pressed = false
	_fly_down_pressed = false
	print("XRLocomotion: Gravity aktiviert")


## Setzt den XRPlayer auf eine bestimmte Weltposition (für Menü-Navigationspunkte).
func set_world_position(world_pos: Vector3) -> void:
	var camera_offset: Vector3 = xr_camera.global_position - global_position
	camera_offset.y = 0.0
	global_position = world_pos - camera_offset
	print("XRLocomotion: Position gesetzt auf %s" % world_pos)
