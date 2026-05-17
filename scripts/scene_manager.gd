## scene_manager.gd
## Autoload-Singleton: Verwaltet das Laden und Wechseln von Architektur-Szenen.
##
## Verwendung:
##   SceneManager.load_scene("res://scenes/environment/haus_eg.tscn")
##   SceneManager.scene_loaded.connect(_on_scene_loaded)

extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal scene_loaded(scene_path: String)
signal scene_load_progress(progress: float)

# ---------------------------------------------------------------------------
# Export-Variablen
# ---------------------------------------------------------------------------

## Standard-Übergangsfarbe (schwarz für professionelle Präsentationen)
@export var fade_color: Color = Color.BLACK
@export var fade_duration: float = 0.4

# ---------------------------------------------------------------------------
# Private Variablen
# ---------------------------------------------------------------------------

var _current_scene_path: String = ""
var _is_loading: bool = false
var _load_queue: Array[String] = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	print("SceneManager: Bereit.")


func _process(_delta: float) -> void:
	if _is_loading and not _load_queue.is_empty():
		_check_load_progress()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Lädt eine neue Architektur-Szene (Background-Loading mit Fortschrittsanzeige).
func load_scene(scene_path: String, use_background_load: bool = true) -> void:
	if _is_loading:
		push_warning("SceneManager: Lädt bereits eine Szene. Anfrage ignoriert.")
		return

	if scene_path == _current_scene_path:
		push_warning("SceneManager: Szene '%s' ist bereits aktiv." % scene_path)
		return

	_is_loading = true

	if use_background_load:
		ResourceLoader.load_threaded_request(scene_path, "PackedScene")
		_load_queue.append(scene_path)
	else:
		# Synchrones Laden (für einfache Szenen)
		var packed: PackedScene = ResourceLoader.load(scene_path, "PackedScene")
		if packed:
			_activate_scene(packed, scene_path)
		else:
			push_error("SceneManager: Konnte Szene nicht laden: %s" % scene_path)
			_is_loading = false


func _check_load_progress() -> void:
	if _load_queue.is_empty():
		return

	var path: String = _load_queue[0]
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = \
			ResourceLoader.load_threaded_get_status(path, progress)

	if not progress.is_empty():
		scene_load_progress.emit(progress[0])

	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
			_load_queue.pop_front()
			_activate_scene(packed, path)

		ResourceLoader.THREAD_LOAD_FAILED:
			push_error("SceneManager: Laden fehlgeschlagen: %s" % path)
			_load_queue.pop_front()
			_is_loading = false

		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pass  # Weiter warten


func _activate_scene(packed: PackedScene, path: String) -> void:
	if packed == null:
		push_error("SceneManager: PackedScene ist null für: %s" % path)
		_is_loading = false
		return

	# Aktuelle Welt-Node austauschen (Player bleibt erhalten)
	var current_scene: Node = get_tree().current_scene
	var world_node: Node = current_scene.find_child("World", false, false)

	if world_node:
		world_node.queue_free()
		await get_tree().process_frame

	var new_world: Node = packed.instantiate()
	new_world.name = "World"
	current_scene.add_child(new_world)
	current_scene.move_child(new_world, 0)  # Vor den Player-Node

	_current_scene_path = path
	_is_loading = false

	print("SceneManager: Szene geladen: %s" % path)
	scene_loaded.emit(path)


## Gibt den Pfad der aktuell geladenen Szene zurück.
func get_current_scene_path() -> String:
	return _current_scene_path


## Gibt true zurück wenn gerade eine Szene geladen wird.
func is_loading() -> bool:
	return _is_loading
