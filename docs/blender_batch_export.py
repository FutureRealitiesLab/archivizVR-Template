import bpy
import os
import uuid

# =============================================================================
# KONFIGURATION – Hier anpassen!
# =============================================================================

export_dir = "C:/Exportordner/"
export_format = 'GLTF'   # 'GLTF' = externe Texturen | 'GLB' = eingebettet | 'FBX'

# =============================================================================
# AB HIER NICHTS ÄNDERN
# =============================================================================

# ── Kontext sicherstellen ────────────────────────────────────────────────────
for window in bpy.context.window_manager.windows:
    for area in window.screen.areas:
        if area.type == 'VIEW_3D':
            ctx = {'window': window, 'screen': window.screen, 'area': area}
            with bpy.context.temp_override(**ctx):
                if bpy.context.object and bpy.context.object.mode != 'OBJECT':
                    bpy.ops.object.mode_set(mode='OBJECT')
            break

def get_view3d_context():
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == 'VIEW_3D':
                for region in area.regions:
                    if region.type == 'WINDOW':
                        return {'window': window, 'screen': window.screen, 'area': area, 'region': region}
    return {}

# ── Exportordner anlegen ─────────────────────────────────────────────────────
if not os.path.exists(export_dir):
    os.makedirs(export_dir)
    print(f"Ordner erstellt: {export_dir}")

scene = bpy.context.scene
ctx = get_view3d_context()

with bpy.context.temp_override(**ctx):
    bpy.ops.object.select_all(action='DESELECT')

exported = []
skipped  = []


# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

def find_layer_collection(layer_coll, target):
    if layer_coll.collection == target:
        return layer_coll
    for child in layer_coll.children:
        result = find_layer_collection(child, target)
        if result:
            return result
    return None


def is_collection_visible(collection):
    view_layer = bpy.context.view_layer
    layer_coll = find_layer_collection(view_layer.layer_collection, collection)
    if layer_coll is None:
        return False
    if layer_coll.exclude:
        return False
    if layer_coll.hide_viewport:
        return False
    if collection.hide_viewport:
        return False
    return True


def realize_instances(instance_objects):
    if not instance_objects:
        return []

    for obj in instance_objects:
        obj.hide_set(True)

    copied_empties = []
    for obj in instance_objects:
        obj.hide_set(False)
        new_obj = obj.copy()
        new_obj.hide_set(False)
        scene.collection.objects.link(new_obj)
        copied_empties.append(new_obj)
        obj.hide_set(True)

    with bpy.context.temp_override(**ctx):
        bpy.ops.object.select_all(action='DESELECT')
    for obj in copied_empties:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = copied_empties[0]

    with bpy.context.temp_override(**ctx):
        bpy.ops.object.duplicates_make_real(
            use_base_parent=False,
            use_hierarchy=True
        )

    realized_meshes = [
        o for o in bpy.context.selected_objects
        if o.type == 'MESH'
    ]
    leftover_empties = [
        o for o in bpy.context.selected_objects
        if o.type == 'EMPTY'
    ]

    with bpy.context.temp_override(**ctx):
        bpy.ops.object.select_all(action='DESELECT')
    for o in leftover_empties + copied_empties:
        if o not in instance_objects:
            o.select_set(True)
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.delete()

    for obj in instance_objects:
        obj.hide_set(False)

    for obj in realized_meshes:
        with bpy.context.temp_override(**ctx):
            bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        with bpy.context.temp_override(**ctx):
            bpy.ops.object.convert(target='MESH')

    return realized_meshes


# =============================================================================
# GODOT .IMPORT GENERIEREN
# =============================================================================

def write_godot_import(gltf_path):
    filename     = os.path.basename(gltf_path)
    import_path  = gltf_path + ".import"
    stem         = os.path.splitext(filename)[0]

    uid_int = uuid.uuid4().int & 0x7FFFFFFFFFFFFFFF
    uid_str = f"uid://{''.join([str((uid_int >> (5*i)) & 31) for i in range(13)])}"
    hex_id  = f"{uid_int:016x}"

    content = f"""[remap]

importer="scene"
importer_version=1
type="PackedScene"
uid="{uid_str}"
path="res://.godot/imported/{stem}-{hex_id}.scn"

[deps]

source_file="res://{filename}"
dest_files=["res://.godot/imported/{stem}-{hex_id}.scn"]

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=2
meshes/lightmap_texel_size=0.1
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
import_script/path=""
_subresources={{}}
"""

    with open(import_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  → Godot .import: {import_path}")


# =============================================================================
# EXPORT PRO COLLECTION
# =============================================================================

def export_collection(collection):
    if not is_collection_visible(collection):
        print(f"  Übersprungen (nicht sichtbar): {collection.name}")
        skipped.append(f"{collection.name} (unsichtbar)")
        return

    mesh_objects = [
        o for o in collection.objects
        if o.type == 'MESH' and o.visible_get()
    ]
    instance_objects = [
        o for o in collection.objects
        if o.type == 'EMPTY'
        and o.instance_type == 'COLLECTION'
        and o.visible_get()
    ]

    if not mesh_objects and not instance_objects:
        print(f"  Übersprungen (keine Mesh-Objekte / Instanzen): {collection.name}")
        skipped.append(collection.name)
    else:
        all_temp_objects = []

        # Normale Meshes duplizieren + Modifier backen
        for obj in mesh_objects:
            new_obj      = obj.copy()
            new_obj.data = obj.data.copy()
            scene.collection.objects.link(new_obj)
            all_temp_objects.append(new_obj)

            with bpy.context.temp_override(**ctx):
                bpy.ops.object.select_all(action='DESELECT')
            new_obj.select_set(True)
            bpy.context.view_layer.objects.active = new_obj
            with bpy.context.temp_override(**ctx):
                bpy.ops.object.convert(target='MESH')

        # Collection Instances realisieren
        if instance_objects:
            print(f"    → {len(instance_objects)} Collection Instance(s) werden realisiert ...")
            realized = realize_instances(instance_objects)
            all_temp_objects.extend(realized)
            print(f"    → {len(realized)} Mesh-Objekt(e) aus Instanzen erzeugt")

        if not all_temp_objects:
            print(f"  Übersprungen (Realisierung ergab keine Meshes): {collection.name}")
            skipped.append(f"{collection.name} (Instanz leer)")
        else:
            with bpy.context.temp_override(**ctx):
                bpy.ops.object.select_all(action='DESELECT')
            for obj in all_temp_objects:
                obj.select_set(True)

            safe_name = collection.name.replace(" ", "_")

            # ── Export ──────────────────────────────────────────────────────
            if export_format == 'GLTF':
                filepath = os.path.join(export_dir, safe_name + ".gltf")
                bpy.ops.export_scene.gltf(
                    filepath=filepath,
                    export_format='GLTF_SEPARATE',
                    use_selection=True,
                    export_apply=True,
                    export_yup=True,
                    export_texcoords=True,
                    export_normals=True,
                    export_tangents=False,
                    export_materials='EXPORT',
                    export_cameras=False,
                    export_lights=False,
                    export_texture_dir="",
                )

            elif export_format == 'GLB':
                filepath = os.path.join(export_dir, safe_name + ".glb")
                bpy.ops.export_scene.gltf(
                    filepath=filepath,
                    export_format='GLB',
                    use_selection=True,
                    export_apply=True,
                    export_yup=True,
                    export_texcoords=True,
                    export_normals=True,
                    export_tangents=False,
                    export_materials='EXPORT',
                    export_cameras=False,
                    export_lights=False,
                )

            elif export_format == 'FBX':
                filepath = os.path.join(export_dir, safe_name + ".fbx")
                bpy.ops.export_scene.fbx(
                    filepath=filepath,
                    use_selection=True,
                    apply_scale_options='FBX_SCALE_ALL',
                    axis_forward='-Z',
                    axis_up='Y',
                )

            ext = '.gltf' if export_format == 'GLTF' else '.glb' if export_format == 'GLB' else '.fbx'
            print(f"  ✓ Exportiert: {filepath}")
            exported.append(safe_name + ext)

            # Godot .import nur für GLTF
            if export_format == 'GLTF':
                write_godot_import(filepath)

            # Temporäre Objekte löschen
            with bpy.context.temp_override(**ctx):
                bpy.ops.object.select_all(action='DESELECT')
            for obj in all_temp_objects:
                obj.select_set(True)
            with bpy.context.temp_override(**ctx):
                bpy.ops.object.delete()

    for child in collection.children:
        print(f"\n--- Sub-Collection: {child.name} ---")
        export_collection(child)


# =============================================================================
# MAIN
# =============================================================================

for collection in scene.collection.children:
    print(f"\n=== Collection: {collection.name} ===")
    export_collection(collection)

print(f"\n{'='*50}")
print(f"Batch-Export abgeschlossen!")
print(f"  Exportiert:    {len(exported)}")
for f in exported:
    print(f"    ✓ {f}")
if skipped:
    print(f"  Übersprungen:  {len(skipped)}")
    for s in skipped:
        print(f"    - {s}")
print(f"  Zielordner:    {export_dir}")
print(f"{'='*50}")
