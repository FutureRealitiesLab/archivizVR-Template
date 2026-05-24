# ArchViz VR – Architecture Documentation

## Project Outline

**ArchViz VR** is a Godot 4.6 template for Architecture Visualization (ArchViz). It supports Meta Quest 2 / PCVR headsets via OpenXR and automatically falls back to a First-Person-View (FPV) desktop controller when no HMD is detected.

The primary goal is a clean, reusable pipeline: export Blender collections as `.gltf` files, drop them into a Godot scene, and let clients walk through the architecture in VR or on a standard monitor.

---

## Directory Structure

```text
archviz_vr/
├── addons/
│   └── godotopenxrvendors/         # Meta OpenXR Vendor Plugin (required for Quest 2!)
├── assets/
│   ├── materials/                  # Shared PBR materials (.tres)
│   ├── textures/                   # albedo, normal, roughness maps
│   ├── meshes/                     # Imported .gltf / .glb assets
│   └── Exportordner/               # Blender batch export target (GLTF + textures)
├── docs/
│   ├── blender-export-guide.md     # Blender export guide (glass, transparency, tips)
│   └── blender_batch_export.py     # Blender Python batch export script
├── scenes/
│   ├── environment/
│   │   ├── a24.tscn                # Current architecture scene
│   │   ├── demo_room.tscn          # Demo placeholder scene
│   │   └── [your scenes]           # Architecture scenes go here
│   ├── player/
│   │   ├── xr_player.tscn          # VR Player (XROrigin3D + xr_locomotion.gd)
│   │   └── fpv_player.tscn         # Desktop Player (CharacterBody3D + fpv_controller.gd)
│   └── main.tscn                   # Root entry point
├── scripts/
│   ├── main.gd                     # Startup orchestration
│   ├── xr_manager.gd               # Autoload: OpenXR lifecycle + rendering config
│   ├── scene_manager.gd            # Autoload: async scene loading/swapping
│   ├── xr_locomotion.gd            # VR locomotion (teleport / smooth / fly / gravity)
│   └── fpv_controller.gd           # Desktop locomotion (walk / fly / crouch)
├── build_quest.bat                 # Force-clean build helper (taskkill + cache clear)
├── project.godot                   # Engine config (OpenXR, rendering, input)
├── export_presets.cfg              # Android / Meta Quest export settings
├── default_action_map.tres         # OpenXR action bindings (14 controller profiles)
└── architecture.md                 # This file
```

---

## Startup Sequence

```
main.gd _ready()
  │
  ├── 1. XRManager signals connected (initialized, mode_changed)
  ├── 2. Player scenes + spawn config set on XRManager
  ├── 3. SceneManager.load_scene(startup_scene, false)  ← synchronous on first load
  ├── 4. await SceneManager.scene_loaded
  └── 5. XRManager.initialize()
            ├── VR detected  → _activate_vr_mode()  → spawn xr_player.tscn
            └── no HMD       → _activate_fpv_mode() → spawn fpv_player.tscn
```

Player spawns as a child of `/root/Main` (not inside `World`) so it survives scene swaps.

---

## System Modules

### `main.gd` / `main.tscn`

Entry point. Responsibilities:
- Wires up `XRManager` signals before initialization
- Assigns player scenes and spawn config to `XRManager` at runtime
- Loads the startup scene synchronously before triggering XR init
- Handles global keyboard shortcuts: `F1` = force FPV, `F2` = performance stats

```gdscript
@export var startup_scene: String = "res://scenes/environment/a24.tscn"
XRManager.player_spawn_parent_path = NodePath("/root/Main")
XRManager.spawn_position = Vector3(0.0, 0.1, 5.0)
```

---

### `XRManager` (Autoload)

Manages OpenXR lifecycle, rendering mode switching, and player spawning.

**Signals:**
| Signal | When |
|---|---|
| `initialized(success: bool)` | After VR/FPV setup completes |
| `mode_changed(new_mode: Mode)` | On any mode transition |

**Public API:**
```gdscript
XRManager.is_vr_active() → bool
XRManager.get_mode()     → Mode  # NONE / VR / FPV
XRManager.get_player()   → Node3D
XRManager.get_camera()   → Camera3D
XRManager.force_fpv_mode()
XRManager.set_render_scale(scale: float)  # 0.5–2.0, live tuning
```

**VR Rendering Profile** (`_configure_rendering_for_vr()`):
| Setting | Value | Reason |
|---|---|---|
| MSAA | 4x | Anti-aliasing |
| TAA | off | Ghosting on head movement |
| Render scale | 1.0 | Quest 2 native per-eye res |
| VRS | disabled | Conflicts with Meta FFR Extension |
| Foveation | Level 2 | Via `project.godot`, handled by vendor plugin |
| Physics FPS | 90 Hz | Matches Quest 2 display rate |
| Tonemapper | Filmic | Warm, cinematic look |
| Glow | on (0.4) | Subtle bloom |
| SDFGI / SSAO / SSR | off | Not available in Mobile renderer |

**FPV Rendering Profile** (`_configure_rendering_for_fpv()`):
| Setting | Value |
|---|---|
| MSAA | 4x |
| TAA | on |
| FXAA | on |
| SDFGI | on |
| SSAO | on |
| SSR | on |
| Physics FPS | 60 Hz |

**OpenXR session signals handled:**
- `session_begun` → sets 90 Hz refresh rate
- `session_stopping` → triggers `force_fpv_mode()` (HMD removed)

---

### `SceneManager` (Autoload)

Handles loading and swapping of architectural environments.

**Signals:**
```gdscript
scene_loaded(scene_path: String)
scene_load_progress(progress: float)  # 0.0–1.0 for UI progress bars
```

**API:**
```gdscript
SceneManager.load_scene(path, use_background_load: bool = true)
SceneManager.get_current_scene_path() → String
SceneManager.is_loading() → bool
```

**Scene swap mechanism:**
1. Finds the `World` child node inside `main.tscn`'s current scene
2. Calls `queue_free()` on it, awaits one process frame
3. Instantiates the new scene, names it `"World"`, adds it as child index 0
4. Player node (at parent `/root/Main`) is untouched during the swap

---

### `xr_locomotion.gd` — VR Player Controller

Attached to `XROrigin3D`. Pure kinematic movement (no physics engine).

**Locomotion modes** (toggle with A button):
- **Teleport**: Right trigger aims via `TeleportRay (RayCast3D)`, release to jump. Validates surface normal (dot > 0.7) and distance (≤ 15 m). Snap-Turn (30°) via right thumbstick.
- **Smooth Locomotion**: Left thumbstick moves relative to HMD yaw. Right thumbstick = smooth continuous turn.

**Rotation – `_rotate_around_camera(angle)`:**
All turns use this helper instead of `rotate_y()`. It compensates for the HMD offset relative to `XROrigin`, ensuring rotation always happens around the player's head — not the Guardian tracking center. This prevents the "orbiting" effect in room-scale / LBE setups.

**Gravity / Floor Snap** (active by default, disabled in fly mode):
- Raycast fires downward from HMD X/Z position (not XROrigin center — correct for LBE)
- `floor_collision_mask = 1` — Godot default Layer 1 for StaticBody3D geometry
- `floor_snap_speed = 8.0` — lerp factor, fast enough for natural gravity feel
- Optional: add nav-plane colliders on Layer 2 for precise stair/ramp control

**Fly Mode** (independent of locomotion mode):
| Button (Quest 2) | Action |
|---|---|
| Y (left, hold) | Fly up — enters fly mode automatically |
| X (left, hold) | Fly down — enters fly mode automatically |
| Left thumbstick click | Exit fly mode, re-enable gravity |

**Full button map (Quest 2):**
| Button | Action |
|---|---|
| Left thumbstick | Move (smooth locomotion) |
| Right thumbstick | Turn (smooth continuous) |
| Right trigger | *(Teleport deaktiviert – für spätere Reaktivierung auskommentiert)* |
| A (right) | Nächste Szene (`SceneChanger.go_next()`) |
| B (right) | Vorherige Szene (`SceneChanger.go_previous()`) |
| Y (left, hold) | Fly up |
| X (left, hold) | Fly down |
| Left thumbstick click | Exit fly mode / enable gravity |

**Key export variables:**
```gdscript
@export var smooth_speed: float = 2.5
@export var fly_speed: float = 2.0
@export var smooth_turn_speed: float = 60.0
@export var snap_turn_angle: float = 30.0
@export var floor_collision_mask: int = 1   # Layer 1 = Godot default
@export var floor_snap_distance: float = 10.0
@export var floor_snap_speed: float = 8.0
@export var max_teleport_distance: float = 15.0
```

---

### `scene_changer.gd` — Szenen-Navigation

Attach to any environment scene as a plain `Node` child. Export-Variablen steuern, welche Szene beim Drücken von A (next) bzw. B (previous) geladen wird.

```gdscript
@export var next_scene: String = ""      # res://scenes/environment/foo.tscn
@export var previous_scene: String = ""  # leer = kein Wechsel in diese Richtung
```

**Verhalten:**
- Registriert sich in der Gruppe `"scene_changer"` – `xr_locomotion.gd` sucht den Node per Gruppen-Lookup, keine harte Referenz nötig.
- **Preload on ready**: startet `ResourceLoader.load_threaded_request()` für `next_scene` und `previous_scene` im Hintergrund, sobald die Szene geladen ist. Beim tatsächlichen Wechsel ist die Ressource bereits im Cache → minimale Wartezeit.
- **Sound**: spielt `assets/mixkit-modern-technology-select-3124.wav` über einen `AudioStreamPlayer` beim Button-Press.
- **"Loading …" Label**: spawnt ein `Label3D` als Kind der aktiven Kamera (VR oder FPV), 1 m vor der Kamera leicht unterhalb der Mitte. Wird automatisch entfernt wenn `SceneManager.scene_loaded` feuert.
- Guard: ignoriert Doppelklicks während ein Load läuft (`SceneManager.is_loading()`).
- Fehlt der Node in einer Szene, passiert bei A/B nichts.

**Neue Szene einbinden:**
1. `SceneChanger`-Node (Typ `Node`, Script `res://scripts/scene_changer.gd`) zur Szene hinzufügen
2. `next_scene` / `previous_scene` als vollständige `res://`-Pfade setzen
3. In der Vorgängerszene `next_scene` auf die neue Szene zeigen lassen

---

### `fpv_controller.gd` — Desktop FPV Controller

Attached to `CharacterBody3D`. Full physics-based walk with optional fly mode.

**Controls:**
| Key | Action |
|---|---|
| WASD / Arrows | Move |
| Mouse | Look |
| Shift | Sprint |
| F | Toggle fly mode |
| Space | Jump (walk mode) |
| E / Q | Up / Down (fly mode) |
| Ctrl | Crouch |
| Escape | Release / recapture mouse |
| F1 | Force FPV (debug) |
| F2 | Performance stats |

In fly mode, `CollisionShape3D` is disabled. Collision mask must include the layer of floor geometry (Layer 1 = Godot default).

---

## Blender → Godot Pipeline

**Script:** [`docs/blender_batch_export.py`](docs/blender_batch_export.py)  
**Guide:** [`docs/blender-export-guide.md`](docs/blender-export-guide.md)

### What the script does

- Iterates all top-level Blender Collections recursively
- Skips invisible collections (`is_collection_visible()`) and hidden objects (`obj.visible_get()`)
- Realizes Collection Instances (linked geometry) into real meshes before export
- Bakes modifiers on temporary duplicates — originals stay untouched
- Exports each collection as a separate file to `export_dir`
- **Auto-generates Godot `.import` files** for GLTF exports (no manual reimport needed)

### Configuration (top of script)

```python
export_dir    = "C:/Exportordner/"
export_format = 'GLTF'   # 'GLTF' | 'GLB' | 'FBX'
```

### Format comparison

| Format | Textures | Godot import | Recommended |
|---|---|---|---|
| GLTF | External files in export_dir | Auto via script | ✅ Yes |
| GLB | Embedded (single file) | Manual in Godot | Production builds |
| FBX | External | Manual in Godot | Avoid |

### Glass / Transparency (Blender 4.2+)

```
Material → Settings → Surface → Render Method: Blended
```
Godot imports `alphaMode: BLEND` automatically. No manual material fix needed.

### Workflow

1. Run script in Blender Scripting tab
2. Copy exported files from `C:/Exportordner/` to `assets/Exportordner/` (or directly there)
3. Godot auto-imports on editor focus (`.import` already generated by script)
4. Drag assets into scene

---

## project.godot – Key Settings

```ini
[application]
run/main_scene = "res://scenes/main.tscn"
config/features = ["4.6", "Mobile"]

[autoload]
XRManager    = "*res://scripts/xr_manager.gd"
SceneManager = "*res://scripts/scene_manager.gd"

[rendering]
renderer/rendering_method = "mobile"          # Vulkan Mobile (required for Quest 2)
anti_aliasing/quality/msaa_3d = 2             # 4x MSAA
textures/default_filters/anisotropic_filtering_level = 4

[xr]
openxr/enabled = true
openxr/foveation_level = 2
openxr/foveation_dynamic = true

[physics]
common/physics_fps = 90
3d/run_on_separate_thread = true
```

---

## Build & Deploy (Meta Quest)

```
1. run build_quest.bat          ← kills Gradle daemon, clears cache
2. Godot Editor → Project → Export → Android (Meta Quest)
   → Export Type: Release       ← IMPORTANT: Debug exports render collision shapes!
3. adb install -r export/archviz_vr.apk
```

`build_quest.bat` uses `taskkill /F /IM java.exe` to reliably kill the Gradle daemon on Windows. `org.gradle.daemon=false` in `gradle.properties` prevents a new daemon from starting.

---

## Adding a New Architecture Scene

1. Run `docs/blender_batch_export.py` in Blender → exports to `C:/Exportordner/`
2. Copy GLTF + textures to `assets/Exportordner/` (or configure `export_dir` to point there directly)
3. Godot auto-imports (`.import` files generated by script)
4. Create new scene in `scenes/environment/`, drag GLTF assets in
5. Add `StaticBody3D` + `CollisionShape3D` on **Collision Layer 1** for walkable floors
6. Add `WorldEnvironment` + `DirectionalLight3D`
7. Add a `SceneChanger` node (type `Node`, script `res://scripts/scene_changer.gd`), set `next_scene` and/or `previous_scene`
8. Set `startup_scene` in `main.gd` or call at runtime:
   ```gdscript
   SceneManager.load_scene("res://scenes/environment/your_scene.tscn")
   ```

---

## TODO / Open Issues

### Web Export – PCK-Größe reduzieren
Aktuell: `ArchViz VR.pck` ~480 MB → zu groß für GitHub Pages (100 MB Limit) und itch.io.

Ursache: unkomprimierte Texturen aus GLTF-Importen landen vollständig im PCK.

Geplante Maßnahmen:
1. **Texturkompression im Web-Export-Preset** (~60–70% Einsparung)
   - `Export → Web → Resources → Texture Format: ETC2 + S3TC, Lossy: ON`
2. **Draco-Kompression auf GLTF** in Blender beim Export (~30–50% Mesh-Einsparung)
3. **Max Texture Size: 1024** für Web-Preset

Ziel: < 100 MB für itch.io-Hosting. GitHub Pages für Web-Deploy ungeeignet (100 MB Dateilimit).

---

## Critical Setup (after cloning)

1. **Android Build Template**: `Godot Editor → Project → Install Android Build Template`
2. **Meta Vendor Plugin**: `Project Settings → Plugins → Godot OpenXR Vendors → Enable`

Without step 2, Quest 2 shows a black screen even if all other settings are correct.

**Common issues:**
- **Collision shapes visible in VR** → exported as Debug build; switch to Release
- **Gravity / floor snap not working** → floor geometry must be on Collision Layer 1
- **Black screen** → check `Project Settings → Rendering` that shading is enabled; check Vendor Plugin is active
- **Rotation orbits around a point** → fixed via `_rotate_around_camera()` — do not use `rotate_y()` directly on XROrigin
