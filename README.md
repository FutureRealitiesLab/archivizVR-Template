# ArchViz VR – Godot 4.6

Architekturvisualisierung in VR und FPV mit Godot 4.6.
Unterstützt OpenXR-kompatible Headsets (Meta Quest, Valve Index, HTC Vive, etc.)
mit automatischem First-Person-View Fallback für Desktop.

---

## ⚠️ Pflicht-Schritte nach dem Klonen

Ohne diese Schritte startet das Projekt auf der Quest **nicht** (schwarzer Screen).

### 1. Android Build Template installieren

Die Godot-Engine-Templates (~200 MB) sind **nicht im Repository** enthalten und müssen lokal installiert werden:

```
Godot Editor öffnen → Project → Install Android Build Template...
```

Dies erzeugt `android/build/libs/godot-lib.template_*.aar` — ohne diese Dateien schlägt der Android-Build fehl.

### 2. Meta OpenXR Vendor Plugin aktivieren

Das Plugin liegt bereits unter `addons/godotopenxrvendors/` im Repo. Es muss einmalig aktiviert werden:

```
Godot Editor → Project → Project Settings → Plugins
→ "Godot OpenXR Vendors" → Enable ✅
```

> **Ohne Vendor Plugin: schwarzer Screen auf Meta Quest** — auch wenn alle anderen Einstellungen korrekt sind. Dies ist der häufigste Fehler bei neuen Projekten.

---

## Szenenbaum-Übersicht

```
Main (Node)                          ← main.tscn / main.gd
├── World (Node3D)                   ← Enthält die geladene Architektur-Szene
│   ├── WorldEnvironment             ← SDFGI/VoxelGI, Tonemap, Glow
│   ├── DirectionalLight3D           ← Sonne (Schatten aktiviert)
│   ├── VoxelGI                      ← Baked GI für VR (oder SDFGI für FPV)
│   └── Geometry (Node3D)            ← Importierte Blender-Meshes
│       ├── Floor (StaticBody3D)
│       ├── Walls (StaticBody3D)
│       └── [Ihre Architektur...]
│
├── [Player wird zur Laufzeit gespawnt vom XRManager]
│   ├── VR:  XRPlayer (XROrigin3D)   ← xr_player.tscn / xr_locomotion.gd
│   │   ├── XRCamera3D
│   │   ├── LeftController (XRController3D)
│   │   └── RightController (XRController3D)
│   │       └── TeleportRay (RayCast3D)
│   └── FPV: FPVPlayer (CharacterBody3D) ← fpv_player.tscn / fpv_controller.gd
│       ├── Head (Node3D)
│       │   └── Camera3D
│       └── CollisionShape3D
│
└── UI (CanvasLayer)                 ← Ladescreen, HUD
    └── LoadingOverlay

Autoloads (global verfügbar):
  XRManager   → scripts/xr_manager.gd
  SceneManager → scripts/scene_manager.gd
```

---

## Projekt-Setup in Godot 4.6

### 1. Voraussetzungen

- **Godot 4.6** (Forward+ Renderer)
- **OpenXR-Runtime** installiert:
  - Meta Quest: Meta Quest Link oder Virtual Desktop
  - SteamVR für Valve Index, HTC Vive
  - Windows Mixed Reality für WMR-Headsets
- Grafikkarte mit Vulkan-Unterstützung (NVIDIA RTX empfohlen für VR)

### 2. Projekt öffnen

```bash
# Projekt klonen
git clone https://github.com/IHR_USERNAME/archviz_vr.git
cd archviz_vr

# In Godot 4.6 öffnen: project.godot auswählen
```

### 3. Autoloads prüfen

`Project → Project Settings → Autoload`:
- `XRManager` → `res://scripts/xr_manager.gd`
- `SceneManager` → `res://scripts/scene_manager.gd`

### 4. OpenXR aktivieren

`Project → Project Settings → XR → OpenXR → Enabled: ON`

---

## Blender → Godot 4.6 Pipeline

> 📄 **Ausführliche Anleitung mit Batch-Export-Script:**
> [docs/blender-export-guide.md](docs/blender-export-guide.md)
> → Exportiert automatisch jede Blender-Collection als separate `.glb`-Datei

### Empfohlener Workflow: glTF 2.0 Export

Dies ist der **offizielle und beste Weg** für Architektur-Assets in Godot 4.6:

#### In Blender:

```
File → Export → glTF 2.0 (.glb/.gltf)

Empfohlene Export-Einstellungen:
✅ Format: .glb (Binary, kompakter)
✅ Include: Geometry (Apply Modifiers: ON)
✅ Geometry: UVs, Normals, Tangents
✅ Materials: Export
✅ Lighting: Standard (kein Unitless)
✅ Compression: Draco (Optional, reduziert Dateigröße ~70%)

Maßstab für Architektur:
- Blender: 1 Unit = 1 Meter (Standard)
- Godot erkennt Maßstab automatisch aus glTF-Metadaten
- Export-Scale: 1.0 (kein Anpassen nötig!)
```

#### Alternativer Direktimport .blend (experimentell):

Godot 4.6 kann `.blend`-Dateien direkt importieren wenn Blender installiert ist.
**Nicht empfohlen für Produktion** – glTF ist stabiler und schneller.

`Project Settings → FileSystem → Import → Blender Path` setzen.

#### Lightmaps in Godot:

Für **vorgebackene Beleuchtung** (beste Qualität, geringste VR-Last):

1. In Blender: UV-Map für Lightmap erstellen (zweiter UV-Kanal)
2. In Blender: Beleuchtung backen (`Cycles → Bake → Combined`)
3. Lightmap-Textur als `albedo` in Godot verwenden (Emission-Slot)
4. Oder: **Godot LightmapGI** nutzen (backt direkt in Godot):

```
Szene → Add Node → LightmapGI
LightmapGI auswählen → Scene → Bake Lightmaps (oben im Viewport)
```

**Für VR: LightmapGI ist die bevorzugte GI-Methode** (vollständig statisch, null Laufzeit-Kosten).

---

## Performance-Optimierungen für VR ArchViz

### Render-Einstellungen (project.godot)

| Einstellung | VR | FPV Desktop |
|---|---|---|
| Renderer | Forward+ | Forward+ |
| MSAA | 4x | 4x |
| TAA | ❌ Aus | ✅ An |
| SSAO | ❌ Aus | ✅ An |
| SDFGI | ❌ Aus | ✅ An |
| VoxelGI | ✅ Baked | Optional |
| LightmapGI | ✅ Bevorzugt | ✅ An |
| FSR 2.2 | 0.75 Scale | Nicht nötig |
| Physics FPS | 90 Hz | 60 Hz |
| Foveated Rendering | Level 2 | N/A |

### Mesh-Optimierung

```
# Empfehlungen für Architektur-Assets:
- LOD (Level of Detail): Für Außenansichten/große Szenen
  → MeshInstance3D → Geometry → LOD Min/Max Pixels

- Occlusion Culling: Bereits in project.godot aktiviert
  → Rooms/Portals oder automatisches Occlusion Culling nutzen

- Draw Calls reduzieren:
  → Meshes zusammenführen (Blender: Ctrl+J vor Export)
  → Gleiche Materialien auf zusammengehörige Flächen
  → MultiMeshInstance3D für wiederholende Elemente (Treppen, Fliesen)

- Polygon-Budget VR (Target: stabile 90 FPS):
  → Gesamt-Szene: < 500.000 Polygone sichtbar
  → Einzelnes Asset: < 50.000 Polygone
  → Verwende Normal Maps statt Geo-Detail
```

### Material-Tipps

```gdscript
# PBR-Materialien für Architektur (in Godot):
# StandardMaterial3D
var mat = StandardMaterial3D.new()
mat.roughness = 0.7          # Mauerwerk: 0.8-1.0, Glas: 0.05
mat.metallic = 0.0           # Beton/Holz: 0.0, Metall: 1.0
mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

# Für Glas/Fenster:
mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
mat.roughness = 0.05
mat.metallic = 0.0
mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
```

---

## GDScript-Kurzreferenz

### XRManager (Autoload)

```gdscript
# Überprüfen ob VR aktiv:
if XRManager.is_vr_active():
    print("VR läuft!")

# Modus abfragen:
var mode = XRManager.get_mode()  # XRManager.Mode.VR oder .FPV

# Player-Node holen:
var player = XRManager.get_player()

# FPV erzwingen (nützlich für Editor-Tests):
XRManager.force_fpv_mode()

# Render-Skala zur Laufzeit anpassen (Performance-Tuning):
XRManager.set_render_scale(0.75)  # 75% = mehr Performance

# Signal verbinden:
XRManager.initialized.connect(func(success): print("VR: ", success))
XRManager.mode_changed.connect(func(mode): print("Modus: ", mode))
```

### SceneManager (Autoload)

```gdscript
# Neue Architektur-Szene laden (Background-Loading):
SceneManager.load_scene("res://scenes/environment/projekt_eg.tscn")

# Ladefortschritt anzeigen:
SceneManager.scene_load_progress.connect(func(p): $ProgressBar.value = p)
SceneManager.scene_loaded.connect(func(path): print("Geladen: ", path))
```

### FPV-Controller (Desktop)

```
WASD / Pfeiltasten  → Bewegen
Maus               → Umsehen
Shift              → Sprint
F                  → Fly-Modus umschalten
E / Q              → Auf-/Abfliegen (Fly-Modus)
Strg               → Ducken
Escape             → Maus freigeben / wieder fangen
F1                 → Force FPV (Debug)
F2                 → Performance-Info
```

### VR-Controller (OpenXR)

```
Linker Thumbstick        → Bewegen (Smooth Locomotion)
Rechter Thumbstick       → Snap-Turn (30°)
Rechter Trigger          → Teleport (zielen + loslassen)
A-Taste (rechts)         → Locomotion-Modus wechseln
X-Taste (links, halten)  → Hoch fliegen (Fly-Modus aktivieren)
Y-Taste (links, halten)  → Runter fliegen (Fly-Modus aktivieren)
B-Taste (rechts)         → Fly-Modus beenden (Gravity an)
Linker Thumbstick (Klick) → Fly-Modus beenden (Gravity an)
```

---

## Projektstruktur

```
archviz_vr/
├── project.godot               ← Projekt-Konfiguration
├── .gitignore
├── README.md
├── scripts/
│   ├── xr_manager.gd           ← Autoload: XR/FPV-Initialisierung & Umschaltung
│   ├── fpv_controller.gd       ← FPV Walk/Fly Controller
│   ├── xr_locomotion.gd        ← VR Teleport/Smooth Locomotion
│   ├── scene_manager.gd        ← Autoload: Szenen-Loading
│   └── main.gd                 ← Haupt-Orchestrierung
├── scenes/
│   ├── main.tscn               ← Haupt-Szene (Einstiegspunkt)
│   ├── player/
│   │   ├── xr_player.tscn      ← VR-Player (XROrigin3D)
│   │   └── fpv_player.tscn     ← FPV-Player (CharacterBody3D)
│   └── environment/
│       ├── demo_room.tscn      ← Demo-Raum (Platzhalter)
│       └── [Ihre Projekte]     ← Architektur-Szenen hier
├── assets/
│   ├── materials/              ← Geteilte PBR-Materialien
│   ├── textures/               ← Texturen (albedo, normal, roughness)
│   └── meshes/                 ← Importierte glTF/GLB-Assets
└── addons/                     ← Godot-Plugins (optional)
```

---

## GitHub Repository einrichten

```bash
cd archviz_vr

# Git initialisieren (falls noch nicht geschehen)
git init
git branch -M main

# Alle Dateien hinzufügen
git add .
git commit -m "Initial commit: ArchViz VR Godot 4.6 Projekt"

# GitHub Remote hinzufügen (URL anpassen)
git remote add origin https://github.com/IHR_USERNAME/archviz_vr.git

# Pushen
git push -u origin main
```

### Git LFS für große Assets (empfohlen)

```bash
git lfs install
git lfs track "*.glb"
git lfs track "*.gltf"
git lfs track "*.hdr"
git lfs track "*.exr"
git lfs track "*.png"
git add .gitattributes
git commit -m "Setup Git LFS für 3D-Assets"
```

---

## Häufige Probleme & Lösungen

**OpenXR startet nicht:**
→ VR-Runtime (SteamVR/Meta Link) muss laufen bevor Godot gestartet wird.
→ Im Log: `XRManager: Wechsle zu FPV` bedeutet FPV-Fallback aktiv.

**VR läuft nicht flüssig (< 90 FPS):**
→ VoxelGI backen statt Echtzeit: `VoxelGI → Bake`
→ Render-Skala auf 0.75 reduzieren (FSR kompensiert die Auflösung)
→ SSAO/SSIL/SSR deaktivieren (macht XRManager automatisch)

**Maßstab stimmt nicht:**
→ In Blender: `Scene → Units → Unit System: Metric, Scale: 1.0`
→ glTF exportieren ohne Scale-Modifikation

**Teleport funktioniert nicht:**
→ StaticBody3D-Kollision auf dem Boden prüfen
→ Collision Layer 1 muss auf dem Boden aktiv sein

---

## Lizenz

MIT License – Freie Verwendung für kommerzielle und private Projekte.
