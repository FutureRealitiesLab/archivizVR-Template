# Blender → Godot 4: Batch-Export nach Collections

Dieses Script exportiert jede Top-Level-Collection in Blender als separate `.glb`-Datei.
Ideal für Architekturprojekte mit klar strukturierten Collections (z.B. `Rohbau`, `Ausbau`, `Außenanlagen`).

---

## Voraussetzungen

- **Blender 4.x** (getestet ab 4.0)
- Modell ist in **Top-Level-Collections** organisiert
- Jede Collection enthält **Mesh-Objekte** (Lights, Cameras werden ignoriert)

---

## ⚠️ Pfad anpassen – Pflicht vor dem ersten Start

Im Script muss **eine Zeile** angepasst werden:

```python
export_dir = "C:/Users/DEIN_NAME/Pfad/zu/deinem/Exportordner/"
```

- **Windows-Pfade** mit Vorwärts-Slashes `/` oder doppelten Rückwärts-Slashes `\\`
- Ordner wird automatisch erstellt falls nicht vorhanden
- Trailing Slash am Ende nicht vergessen

---

## Das Script

```python
import bpy
import os

# =============================================================================
# KONFIGURATION – Hier anpassen!
# =============================================================================

# ⚠️ PFAD ANPASSEN: Zielordner für die exportierten .glb-Dateien
export_dir = "C:/Users/DEIN_NAME/Pfad/zu/deinem/Exportordner/"

# Exportformat: 'GLTF' (empfohlen für Godot) oder 'FBX'
export_format = 'GLTF'

# =============================================================================
# AB HIER NICHTS ÄNDERN
# =============================================================================

# Exportordner erstellen falls nicht vorhanden
if not os.path.exists(export_dir):
    os.makedirs(export_dir)
    print(f"Ordner erstellt: {export_dir}")

scene = bpy.context.scene
bpy.ops.object.select_all(action='DESELECT')

exported = []
skipped = []

for collection in scene.collection.children:
    print(f"\n--- Collection: {collection.name} ---")

    # Leere Collections überspringen
    mesh_objects = [o for o in collection.objects if o.type == 'MESH']
    if not mesh_objects:
        print(f"  Übersprungen (keine Mesh-Objekte)")
        skipped.append(collection.name)
        continue

    copied_objects = []

    # 1. Objekte duplizieren und Modifier einbacken
    for obj in mesh_objects:
        new_obj = obj.copy()
        new_obj.data = obj.data.copy()
        scene.collection.objects.link(new_obj)
        copied_objects.append(new_obj)

        bpy.ops.object.select_all(action='DESELECT')
        new_obj.select_set(True)
        bpy.context.view_layer.objects.active = new_obj
        bpy.ops.object.convert(target='MESH')

    # 2. Kopien für Export selektieren
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copied_objects:
        obj.select_set(True)

    # 3. Dateiname: Leerzeichen → Unterstrich, Sonderzeichen entfernen
    safe_name = collection.name.replace(" ", "_")
    file_extension = ".glb" if export_format == 'GLTF' else ".fbx"
    filepath = os.path.join(export_dir, safe_name + file_extension)

    # 4. Export
    if export_format == 'GLTF':
        bpy.ops.export_scene.gltf(
            filepath=filepath,
            export_format='GLB',
            use_selection=True,
            export_apply=True,          # Modifier sicherheitshalber nochmals anwenden
            export_yup=True,            # Y-up für Godot/glTF-Standard
            export_texcoords=True,      # UV-Maps exportieren
            export_normals=True,        # Normalen exportieren
            export_tangents=False,      # Tangenten (nur nötig bei Normal Maps)
            export_materials='EXPORT',  # Materialien mitnehmen
            export_colors=False,        # Vertex Colors (meist nicht nötig)
            export_cameras=False,
            export_lights=False,
        )
    elif export_format == 'FBX':
        bpy.ops.export_scene.fbx(
            filepath=filepath,
            use_selection=True,
            apply_scale_options='FBX_SCALE_ALL',
            axis_forward='-Z',
            axis_up='Y',
        )

    print(f"  ✓ Exportiert: {filepath}")
    exported.append(safe_name + file_extension)

    # 5. Temporäre Kopien löschen
    if copied_objects:
        bpy.ops.object.delete()

# Zusammenfassung
print(f"\n{'='*50}")
print(f"Batch-Export abgeschlossen!")
print(f"  Exportiert: {len(exported)} Collections")
if exported:
    for f in exported:
        print(f"    ✓ {f}")
if skipped:
    print(f"  Übersprungen (leer): {len(skipped)}")
    for s in skipped:
        print(f"    - {s}")
print(f"  Zielordner: {export_dir}")
print(f"{'='*50}")
```

---

## Verwendung in Blender

### Option A: Über den Text Editor (empfohlen)

1. **Scripting**-Workspace öffnen (Tab oben in Blender)
2. **New** → Script-Text aus dieser Anleitung einfügen
3. `export_dir` anpassen
4. **Run Script** (▶) oder `Alt + P`
5. Fortschritt im **Info-Log** (unten) verfolgen

### Option B: Über die Konsole (Windows)

```bash
blender --background mein_projekt.blend --python blender_batch_export.py
```

Nützlich für automatisierte Pipelines ohne Blender-GUI.

---

## Was das Script tut (Schritt für Schritt)

```
Für jede Top-Level-Collection:
  │
  ├── Leere Collections → überspringen
  │
  ├── 1. Für jedes Mesh-Objekt:
  │       - Duplikat erstellen (Original bleibt unverändert)
  │       - Alle Modifier einbacken (Subdivision Surface, Boolean, etc.)
  │
  ├── 2. Alle Duplikate selektieren
  │
  ├── 3. Dateiname erstellen
  │       - Collection-Name: "Wand Innen" → Datei: "Wand_Innen.glb"
  │
  ├── 4. Als .glb exportieren (nur selektierte Objekte)
  │
  └── 5. Duplikate löschen (Original-Szene bleibt sauber)
```

---

## Collections sinnvoll strukturieren

Empfohlene Aufteilung für Architekturprojekte:

```
Scene Collection
├── Rohbau          → Rohbau.glb
├── Ausbau          → Ausbau.glb  
├── Fassade         → Fassade.glb
├── Aussenanlagen   → Aussenanlagen.glb
└── Moebel          → Moebel.glb
```

**Wichtig:** Nur **Top-Level-Collections** werden exportiert (direkte Kinder von `Scene Collection`).
Verschachtelte Sub-Collections werden mit ihrer Parent-Collection zusammen exportiert.

---

## Import in Godot 4

1. Exportierte `.glb`-Dateien nach `res://assets/meshes/` kopieren
2. Godot importiert automatisch beim nächsten Editor-Fokus
3. In der Szene: `MeshInstance3D` → **Mesh** → `.glb`-Datei zuweisen
4. Oder: `.glb`-Datei direkt in den Szenenbaum ziehen

### Empfohlene Import-Einstellungen in Godot

```
Datei auswählen → Import-Tab (rechts oben):

Meshes:
  ✅ Generate LODs           → automatische LODs für Performance
  ✅ Create Shadow Meshes    → optimierte Schattengeometrie

Materials:
  → Wenn Materialien aus Blender kommen: "Keep on Reimport"
  → Für eigene Godot-Materialien: "Do not Import"

Lights & Cameras:
  ❌ Import Lights           → Beleuchtung lieber direkt in Godot setzen
  ❌ Import Cameras
```

---

## Häufige Probleme

**Script läuft durch aber keine Dateien erscheinen:**
→ Pfad prüfen – Windows: `C:/Users/...` oder `C:\\Users\\...` (kein `\` einzeln)
→ Schreibrechte auf den Zielordner prüfen

**Objekte fehlen im Export:**
→ Nur `MESH`-Objekte werden exportiert (keine Curves, Empties, Lights)
→ Curves vorher mit `Alt+C → Mesh` konvertieren

**Maßstab stimmt nicht in Godot:**
→ In Blender: `Scene Properties → Units → Unit System: Metric, Length: Meters`
→ Objekte auf `Scale: 1,1,1` bringen: `Ctrl+A → Apply Scale`

**Modifier werden nicht angewendet:**
→ Script wendet Modifier automatisch an – Originale bleiben unverändert
→ Bei Geometry Nodes: sicherstellen dass sie im `MESH`-Output enden

**Leerzeichen im Collection-Namen:**
→ Werden automatisch durch `_` ersetzt (`Wand Innen` → `Wand_Innen.glb`)
