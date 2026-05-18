# ArchViz VR – Architecture Documentation

## Project Outline

**ArchViz VR** is a Godot 4.6 template for Architecture Visualization (ArchViz). It supports Meta Quest 2 / PCVR headsets via OpenXR and automatically falls back to a First-Person-View (FPV) desktop controller when no HMD is detected.

The primary goal is a clean, reusable pipeline: import Blender-exported `.glb` files, drop them into a scene, and let clients walk through the architecture in VR or on a standard monitor.

---

## Directory Structure

```text
archviz_vr/
├── addons/
│   └── godotopenxrvendors/     # Meta OpenXR Vendor Plugin (required for Quest 2!)
├── assets/
│   ├── materials/              # Shared PBR materials (.tres)
│   ├── textures/               # albedo, normal, roughness maps
│   └── meshes/                 # Imported .glb / .gltf assets
├── docs/
│   └── blender-export-guide.md # Blender batch export guide (Python script + glass tips)
├── scenes/
│   ├── environment/
│   │   ├── demo_room.tscn      # Demo placeholder scene
│   │   └── [your scenes]       # Architecture scenes go here
│   ├── player/
│   │   ├── xr_player.tscn      # VR Player (XROrigin3D + xr_locomotion.gd)
│   │   └── fpv_player.tscn     # Desktop Player (CharacterBody3D + fpv_controller.gd)
│   └── main.tscn               # Root entry point
├── scripts/
│   ├── main.gd                 # Startup orchestration
│   ├── xr_manager.gd           # Autoload: OpenXR lifecycle + rendering config
│   ├── scene_manager.gd        # Autoload: async scene loading/swapping
│   ├── xr_locomotion.gd        # VR locomotion (teleport / smooth / fly)
│   └── fpv_controller.gd       # Desktop locomotion (walk / fly / crouch)
├── build_quest.bat             # Force-clean build helper (taskkill + cache clear)
├── project.godot               # Engine config (OpenXR, rendering, input)
├── export_presets.cfg          # Android / Meta Quest export settings
├── default_action_map.tres     # OpenXR action bindings (14 controller profiles)
└── architecture.md             # This file
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
| MSAA | 4x | Anti-aliasing without TAA ghosting |
| TAA | off | Causes ghosting on head movement |
| Scaling mode | Bilinear | FSR2 not supported on Mobile renderer |
| Render scale | 1.0 | Quest 2 native per-eye res is already high |
| VRS | disabled | `VRS_XR` conflicts with Meta FFR Extension |
| Foveation | Level 2 | Set in `project.godot`, handled by vendor plugin |
| Physics FPS | 90 Hz | Matches Quest 2 display rate |
| Tonemapper | Filmic | Warm, cinematic look for architecture |
| Glow | on (0.4 intensity) | Subtle bloom on lights and bright surfaces |
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

Attached to `XROrigin3D`. Pure kinematic movement (no physics/gravity).

**Locomotion modes** (toggle with A button):
- **Teleport**: Right trigger aims via `TeleportRay (RayCast3D)`, release to jump. Validates surface normal (dot > 0.7) and distance (≤ 15 m).
- **Smooth Locomotion**: Left thumbstick moves relative to HMD yaw. Right thumbstick turns (smooth or snap).

**Fly Mode** (independent of locomotion mode):
| Button (Quest 2) | Action |
|---|---|
| Y (left, hold) | Move up — enters fly mode automatically |
| X (left, hold) | Move down — enters fly mode automatically |
| B (right) | Exit fly mode, re-enable gravity |
| Left thumbstick click | Exit fly mode, re-enable gravity |

While fly mode is active, vertical movement is applied every physics frame at `fly_speed` (2.0 m/s, configurable). Releasing Y/X stops vertical movement but keeps the player at the current height. Fly mode is independent of teleport/smooth mode.

**Gravity / Floor Snap** (active by default, disabled in fly mode):
- Raycast fires downward from HMD X/Z position (not XROrigin center — important for LBE)
- `floor_collision_mask = 1` — matches Godot's default Layer 1 for StaticBody3D geometry
- `floor_snap_speed = 8.0` — lerp factor, fast enough to feel like natural gravity
- Optional: add separate nav-plane colliders on Layer 2 for precise stair/ramp control

**Full button map (Quest 2):**
| Button | Action |
|---|---|
| Left thumbstick | Move (smooth locomotion) |
| Right thumbstick | Turn |
| Right trigger | Teleport aim / confirm |
| A (right) | Toggle Teleport ↔ Smooth |
| B (right) | Exit fly mode / enable gravity |
| Y (left, hold) | Fly up |
| X (left, hold) | Fly down |
| Left thumbstick click | Exit fly mode / enable gravity |

**Export variables:**
```gdscript
@export var smooth_speed: float = 2.5
@export var fly_speed: float = 2.0
@export var smooth_turn_speed: float = 60.0
@export var snap_turn_angle: float = 30.0
@export var max_teleport_distance: float = 15.0
@export var comfort_vignette: bool = true
```

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

**Key export variables:**
```gdscript
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 7.0
@export var fly_speed: float = 5.0
@export var eye_height: float = 1.75
@export var step_height: float = 0.35
```

In fly mode, `CollisionShape3D` is disabled for free movement through geometry.

---

## Blender → Godot Pipeline

See [`docs/blender-export-guide.md`](docs/blender-export-guide.md) for the full batch export script.

**Summary:**
- Export each Blender Collection as a separate `.glb` via Python script
- Only visible collections and objects are exported (`is_collection_visible()` + `obj.visible_get()`)
- Modifiers are baked on temporary duplicates; originals stay clean
- **Glass/Transparency:** Set `Render Method: Blended` in Material → Settings → Surface (Blender 4.2+)
- Import `.glb` files into `assets/meshes/`, Godot auto-imports on editor focus

---

## project.godot – Key Settings

```ini
[application]
run/main_scene = "res://scenes/main.tscn"
config/features = ["4.6", "Mobile"]

[autoload]
XRManager  = "*res://scripts/xr_manager.gd"
SceneManager = "*res://scripts/scene_manager.gd"

[rendering]
renderer/rendering_method = "mobile"          # Vulkan Mobile (required for Quest 2)
anti_aliasing/quality/msaa_3d = 2             # 4x MSAA
textures/default_filters/anisotropic_filtering_level = 4
gi/use_half_resolution = true

[xr]
openxr/enabled = true
openxr/foveation_level = 2
openxr/foveation_dynamic = true

[physics]
common/physics_fps = 90
3d/run_on_separate_thread = true
```

---

## Adding a New Architecture Scene

1. Export from Blender as `.glb` (use `docs/blender-export-guide.md` for batch export)
2. Copy `.glb` to `assets/meshes/` — Godot auto-imports
3. Create a new scene in `scenes/environment/`, add a `Node3D` root named to match your project
4. Drag `.glb` into the scene, add `StaticBody3D` + `CollisionShape3D` for walkable floors
5. Add `WorldEnvironment` + `DirectionalLight3D`
6. Set `startup_scene` in `main.gd` or call at runtime:
   ```gdscript
   SceneManager.load_scene("res://scenes/environment/your_scene.tscn")
   ```

---

## Build & Deploy (Meta Quest)

```
1. Run build_quest.bat          ← kills Gradle daemon, clears cache
2. Godot Editor → Project → Export → Android (Meta Quest)
   → Export Type: Release  ← IMPORTANT: Debug exports render collision shapes!
3. adb install -r export/archviz_vr.apk
```

`build_quest.bat` uses `taskkill /F /IM java.exe` to reliably kill the Gradle daemon on Windows — more reliable than `gradlew --stop`. `org.gradle.daemon=false` in `gradle.properties` prevents a new daemon from starting.

---

## TODO / Open Issues

### Web Export – PCK-Größe reduzieren
Aktuell: `ArchViz VR.pck` ~480 MB → zu groß für GitHub Pages (100 MB Limit) und itch.io-Standard.

Ursache: unkomprimierte Texturen aus GLB-Importen landen vollständig im PCK.

Geplante Maßnahmen (in dieser Reihenfolge testen):
1. **Texturkompression im Web-Export-Preset** (größter Hebel, ~60–70% Einsparung)
   - `Project → Export → Web → Resources → Texture Format: ETC2 + S3TC + BPTC, Lossy: ON (0.7)`
2. **Draco-Kompression auf GLB** (in Blender beim Re-Export, ~30–50% Mesh-Einsparung)
   - `Blender → Export glTF → Geometry → Compression: Draco`
3. **Max Texture Size: 1024** für Web-Preset (Import-Einstellung, nur für Web-Target)

Ziel: < 100 MB für GitHub Pages, < 200 MB für itch.io.
Hosting-Empfehlung: itch.io als Web-Host (bis 1 GB), GitHub nur als Code-Repo.

---

## Critical Setup (after cloning)

1. **Android Build Template**: `Godot Editor → Project → Install Android Build Template`
2. **Meta Vendor Plugin**: `Project Settings → Plugins → Godot OpenXR Vendors → Enable`

Without step 2, Quest 2 shows a black screen even if all other settings are correct.

**Common issues:**
- **Collision shapes visible in VR** → exported as Debug build; switch to Release
- **Gravity/floor snap not working** → floor geometry must be on Collision Layer 1 (Godot default)
- **Black screen** → check `Project Settings → Rendering → Shading` is enabled
