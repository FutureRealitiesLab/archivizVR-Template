## fpv_controller.gd
## First-Person-View Controller für Desktop (Maus + Tastatur).
## Unterstützt Walk- und Fly-Modus – ideal für Architektur-Präsentationen.
##
## Szenenbaum:
##   FPVPlayer (CharacterBody3D) ← dieses Skript
##   └── Head (Node3D)           ← vertikale Kamera-Rotation
##       └── Camera3D            ← Haupt-Kamera
##   └── CollisionShape3D
##   └── StairStepHelper (ShapeCast3D)

extends CharacterBody3D

# ---------------------------------------------------------------------------
# Export-Variablen (im Godot-Inspector einstellbar)
# ---------------------------------------------------------------------------

@export_group("Bewegung")
## Normale Gehgeschwindigkeit in m/s (1 Godot-Unit = 1 Meter empfohlen für Archviz)
@export var walk_speed: float = 3.0
## Laufgeschwindigkeit (Shift gedrückt)
@export var sprint_speed: float = 7.0
## Geschwindigkeit im Fly-Modus
@export var fly_speed: float = 5.0
## Beschleunigung (wie schnell Maximalgeschwindigkeit erreicht wird)
@export var acceleration: float = 10.0
## Bremsverzögerung
@export var deceleration: float = 16.0
## Sprungkraft (nur im Walk-Modus)
@export var jump_velocity: float = 4.0

@export_group("Kamera")
## Mausempfindlichkeit
@export var mouse_sensitivity: float = 0.002
## Maximale Kamera-Neigung nach oben/unten (Grad)
@export var max_pitch_degrees: float = 85.0
## FOV im Walk-Modus
@export var walk_fov: float = 75.0
## FOV im Fly-Modus
@export var fly_fov: float = 80.0
## Geschwindigkeit der FOV-Interpolation
@export var fov_smooth_speed: float = 5.0

@export_group("Architektur-Präsentation")
## Minimale Augenhöhe (für Sitzen/Ducken)
@export var crouch_height: float = 1.0
## Normale Augenhöhe
@export var eye_height: float = 1.75
## Treppen-Kletter-Höhe in Metern
@export var step_height: float = 0.35

# ---------------------------------------------------------------------------
# Node-Referenzen
# ---------------------------------------------------------------------------

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D

# ---------------------------------------------------------------------------
# Private Variablen
# ---------------------------------------------------------------------------

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _current_speed: float = walk_speed
var _is_fly_mode: bool = false
var _pitch: float = 0.0   # Vertikale Kamera-Rotation in Radians
var _target_fov: float = walk_fov
var _is_crouching: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Kamera einrichten
	camera.fov = walk_fov
	_target_fov = walk_fov

	# Head-Position auf Augenhöhe
	head.position.y = eye_height

	# Input: Maus fangen (wird vom XRManager aufgerufen, hier als Sicherung)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	print("FPVController: Initialisiert. WASD=Bewegen, F=Fly, Shift=Sprint, " +
			"Escape=Maus freigeben, Ctrl=Ducken")


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Maus-Look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_mouse_look(event as InputEventMouseMotion)
		get_viewport().set_input_as_handled()

	# Maus freigeben / wieder fangen (für UI)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Fly-Modus umschalten
	if event.is_action_pressed("toggle_fly"):
		_toggle_fly_mode()

	# Ducken
	if event.is_action_pressed("crouch", false, true):
		_set_crouch(true)
	elif event.is_action_released("crouch"):
		_set_crouch(false)


func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	# Horizontale Rotation: gesamte CharacterBody3D drehen
	rotate_y(-event.relative.x * mouse_sensitivity)

	# Vertikale Rotation: nur Head-Node neigen
	_pitch -= event.relative.y * mouse_sensitivity
	_pitch = clampf(_pitch, deg_to_rad(-max_pitch_degrees), deg_to_rad(max_pitch_degrees))
	head.rotation.x = _pitch

# ---------------------------------------------------------------------------
# Physics Process
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _is_fly_mode:
		_process_fly_movement(delta)
	else:
		_process_walk_movement(delta)

	# FOV sanft interpolieren
	camera.fov = lerpf(camera.fov, _target_fov, delta * fov_smooth_speed)


func _process_walk_movement(delta: float) -> void:
	# Schwerkraft
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	# Springen
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Bewegungsrichtung
	var input_dir: Vector2 = _get_movement_input()
	var direction: Vector3 = _input_to_world_direction(input_dir)

	# Sprint
	var target_speed: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if _is_crouching:
		target_speed *= 0.5

	# Velocity glätten
	if direction != Vector3.ZERO:
		_current_speed = lerpf(_current_speed, target_speed, delta * acceleration)
		velocity.x = direction.x * _current_speed
		velocity.z = direction.z * _current_speed
		_target_fov = walk_fov + (sprint_speed - walk_speed) * 1.5 \
				if Input.is_action_pressed("sprint") else walk_fov
	else:
		_current_speed = lerpf(_current_speed, 0.0, delta * deceleration)
		velocity.x = lerpf(velocity.x, 0.0, delta * deceleration)
		velocity.z = lerpf(velocity.z, 0.0, delta * deceleration)
		_target_fov = walk_fov

	move_and_slide()


func _process_fly_movement(delta: float) -> void:
	# Im Fly-Modus: keine Schwerkraft, Bewegung in Blickrichtung
	var input_dir: Vector2 = _get_movement_input()

	# Horizontale Bewegung in Kamera-Richtung
	var forward: Vector3 = -camera.global_transform.basis.z
	var right: Vector3 = camera.global_transform.basis.x

	# Vertikale Eingabe (E/Q oder Space/Ctrl)
	var up_input: float = 0.0
	if Input.is_action_pressed("move_up"):
		up_input = 1.0
	elif Input.is_action_pressed("move_down"):
		up_input = -1.0

	var target_velocity: Vector3 = (
		forward * (-input_dir.y) +
		right * input_dir.x +
		Vector3.UP * up_input
	) * fly_speed

	velocity = velocity.lerp(target_velocity, delta * acceleration)
	move_and_slide()

	_target_fov = fly_fov

# ---------------------------------------------------------------------------
# Hilfsmethoden
# ---------------------------------------------------------------------------

func _get_movement_input() -> Vector2:
	return Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)


func _input_to_world_direction(input: Vector2) -> Vector3:
	## Wandelt 2D-Eingabe in Weltrichtung um (relativ zur Kamera-Yaw).
	var direction: Vector3 = Vector3.ZERO
	if input != Vector2.ZERO:
		direction = (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	return direction


func _toggle_fly_mode() -> void:
	_is_fly_mode = not _is_fly_mode
	velocity = Vector3.ZERO

	if _is_fly_mode:
		# Kollision deaktivieren für freies Fliegen
		collision.disabled = true
		print("FPVController: Fly-Modus aktiviert")
	else:
		# Kollision wieder aktivieren, Spieler sicher auf Boden setzen
		collision.disabled = false
		print("FPVController: Walk-Modus aktiviert")


func _set_crouch(crouching: bool) -> void:
	_is_crouching = crouching
	var target_height: float = crouch_height if crouching else eye_height
	# Sanfte Kopf-Interpolation (wird in _process gehandelt wenn gewünscht)
	head.position.y = target_height


## Teleportiert den Spieler zu einer Position (für Menü-Navigationspunkte).
func teleport_to(world_position: Vector3, look_direction: Vector3 = Vector3.FORWARD) -> void:
	global_position = world_position
	velocity = Vector3.ZERO

	if look_direction != Vector3.ZERO:
		look_at(global_position + look_direction.normalized(), Vector3.UP)

	print("FPVController: Teleportiert zu %s" % world_position)
