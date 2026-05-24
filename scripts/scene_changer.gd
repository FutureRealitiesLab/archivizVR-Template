class_name SceneChanger
extends Node

@export var next_scene: String = ""
@export var previous_scene: String = ""

var _audio: AudioStreamPlayer

func _ready() -> void:
	add_to_group("scene_changer")
	_preload_scenes()
	_setup_audio()

func go_next() -> void:
	if next_scene != "":
		_trigger(next_scene)

func go_previous() -> void:
	if previous_scene != "":
		_trigger(previous_scene)

func _preload_scenes() -> void:
	for path in [next_scene, previous_scene]:
		if path != "":
			ResourceLoader.load_threaded_request(path, "PackedScene")

func _setup_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.stream = load("res://assets/mixkit-modern-technology-select-3124.wav")
	add_child(_audio)

func _trigger(scene_path: String) -> void:
	if SceneManager.is_loading():
		return
	if _audio.stream:
		_audio.play()
	_show_loading_label()
	SceneManager.load_scene(scene_path)

func _show_loading_label() -> void:
	var camera := XRManager.get_camera()
	if camera == null:
		return
	var label := Label3D.new()
	label.text = "Loading ..."
	label.pixel_size = 0.0015
	label.font_size = 32
	label.outline_size = 6
	label.modulate = Color.WHITE
	label.position = Vector3(0.0, -0.12, -1.0)
	camera.add_child(label)
	SceneManager.scene_loaded.connect(
		func(_p: String) -> void:
			if is_instance_valid(label):
				label.queue_free(),
		CONNECT_ONE_SHOT
	)
