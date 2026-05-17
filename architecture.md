# ArchViz VR - Architecture Documentation

## Project Outline
**ArchViz VR** is a Godot 4-based template project specifically designed for Architecture Visualization (ArchViz). It serves as a foundational boilerplate for presenting architectural scenes in Virtual Reality (Meta Quest 3 / PCVR), while automatically providing a First-Person View (FPV) fallback for standard desktop use if no VR headset is detected. 

The primary goal of this template is to simplify the pipeline for importing architectural models and letting clients walk through them seamlessly either in full VR or via a standard monitor and mouse/keyboard setup.

## Core Features
1. **Hybrid Rendering Strategy**:
   - **VR Mode (Quest 3 Optimized)**: Uses the Mobile renderer, disables expensive post-processing (like FSR2 and Glow), forces Bilinear scaling, and leverages Variable Rate Shading (VRS) and 90Hz refresh rate to ensure solid performance on standalone headsets.
   - **FPV Mode (Desktop)**: Uses MSAA, TAA, SDFGI (Global Illumination), SSAO, and Screen-Space Reflections (SSR) to maximize visual fidelity when running on a PC.
2. **Automatic Fallback**: The `XRManager` automatically detects the presence of an OpenXR compatible headset. If initialization fails, it seamlessly falls back to the FPV desktop controller.
3. **Dynamic Scene Loading**: Environments are loaded inside a dedicated `World` node, allowing architecture models to be swapped asynchronously without destroying the active Player controller or VR session.

## Directory Structure
```text
archviz_vr/
├── addons/                 # Third-party Godot addons (e.g., Godot XR Tools)
├── assets/                 # Textures, 3D models, and materials for architectural scenes
├── scenes/
│   ├── environment/        # Architectural environments (e.g., demo_room.tscn)
│   ├── player/             # Player controllers (xr_player.tscn, fpv_player.tscn)
│   └── main.tscn           # Root entry point of the game
├── scripts/
│   ├── main.gd             # Main orchestrator script
│   ├── xr_manager.gd       # Singleton for OpenXR & rendering state
│   ├── scene_manager.gd    # Singleton for async environment loading
│   ├── fpv_controller.gd   # Logic for desktop mouse/keyboard movement
│   └── xr_locomotion.gd    # Logic for VR teleportation / smooth locomotion
├── project.godot           # Godot project configuration
├── export_presets.cfg      # Export configurations (e.g., Android / Meta Quest 3)
└── architecture.md         # This documentation file
```

## System Modules & Autoloads

### 1. `main.gd` / `main.tscn`
The entry point of the application. The `main.gd` script orchestrates the startup sequence:
1. Requests `SceneManager` to synchronously load the initial architectural scene.
2. Awaits the `SceneManager.scene_loaded` signal to ensure the world is built.
3. Calls `XRManager.initialize()` to detect the platform (VR or FPV) and spawn the appropriate player controller inside the newly created `World` node.

### 2. `XRManager` (Autoload Singleton)
Manages the OpenXR lifecycle and rendering pipelines.
- **Initialization**: Tries to start `OpenXRInterface`. If successful, sets up the viewport for VR. If not, sets up the viewport for FPV desktop use.
- **Rendering Optimization**: Contains explicit profiles `_configure_rendering_for_vr()` and `_configure_rendering_for_fpv()` to toggle graphic settings (SDFGI, VRS, MSAA) based on the active mode.
- **Player Spawning**: Instantiates either `xr_player.tscn` or `fpv_player.tscn` and places them in the current environment at the designated `spawn_position`.

### 3. `SceneManager` (Autoload Singleton)
Handles the loading and unloading of architectural environments.
- **Asynchronous Loading**: Can load heavy architectural models in the background without freezing the application.
- **World Swapping**: Uses a dedicated `World` node in `main.tscn` as a container. When a new scene is loaded, the old `World` node is freed (`queue_free()`) and the new one is instantiated in its place. The Player node remains untouched during this transition.

### 4. Player Controllers
- **XR Player**: Uses `XROrigin3D` and `XRCamera3D` tied to the physical headset. Locomotion is driven by `xr_locomotion.gd` for VR interaction.
- **FPV Player**: Uses a `CharacterBody3D` with standard WASD and Mouse-look input, processed via `fpv_controller.gd`.

## Workflow for Adding New Scenes
1. Import the architectural model (GLTF, blend, etc.) into `assets/`.
2. Create a new Inherited Scene or build a Godot scene and save it in `scenes/environment/`.
3. Set up collisions and ensure lighting parameters match the project needs.
4. Update `startup_scene` in `main.gd` or use `SceneManager.load_scene("res://scenes/environment/your_scene.tscn")` to transition to it at runtime.
