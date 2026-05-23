import bpy
import os

# =============================================================================
# KONFIGURATION – Hier anpassen!
# =============================================================================

export_dir = "C:/Exportordner/"
export_format = 'GLTF'   # 'GLTF' = externe Texturen | 'GLB' = alles eingebettet | 'FBX'

# =============================================================================
# AB HIER NICHTS ÄNDERN
# =============================================================================

if not os.path.exists(export_dir):
    os.makedirs(export_dir)
    print(f"Ordner erstellt: {export_dir}")

scene = bpy.context.scene
bpy.ops.object.select_all(action='DESELECT')

exported = []
skipped = []


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

    bpy.ops.object.select_all(action='DESELECT')
    for obj in copied_empties:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = copied_empties[0]

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

    bpy.ops.object.select_all(action='DESELECT')
    for o in leftover_empties + copied_empties:
        if o not in instance_objects:
            o.select_set(True)
    bpy.ops.object.delete()

    for obj in instance_objects:
        obj.hide_set(False)

    for obj in realized_meshes:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target='MESH')

    return realized_meshes


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

        for obj in mesh_objects:
            new_obj = obj.copy()
            new_obj.data = obj.data.copy()
            scene.collection.objects.link(new_obj)
            all_temp_objects.append(new_obj)

            bpy.ops.object.select_all(action='DESELECT')
            new_obj.select_set(True)
            bpy.context.view_layer.objects.active = new_obj
            bpy.ops.object.convert(target='MESH')

        if instance_objects:
            print(f"    → {len(instance_objects)} Collection Instance(s) werden realisiert ...")
            realized = realize_instances(instance_objects)
            all_temp_objects.extend(realized)
            print(f"    → {len(realized)} Mesh-Objekt(e) aus Instanzen erzeugt")

        if not all_temp_objects:
            print(f"  Übersprungen (Realisierung ergab keine Meshes): {collection.name}")
            skipped.append(f"{collection.name} (Instanz leer)")
        else:
            bpy.ops.object.select_all(action='DESELECT')
            for obj in all_temp_objects:
                obj.select_set(True)

            safe_name = collection.name.replace(" ", "_")

            if export_format == 'GLTF':
                # ── GLTF mit externen Texturen ──────────────────────────────
                # Alle Dateien (.gltf + .bin + textures/) landen direkt im
                # export_dir – kein Unterordner pro Collection.
                filepath = os.path.join(export_dir, safe_name + ".gltf")

                bpy.ops.export_scene.gltf(
                    filepath=filepath,
                    export_format='GLTF_SEPARATE',   # ← externe Texturen
                    use_selection=True,
                    export_apply=True,
                    export_yup=True,
                    export_texcoords=True,
                    export_normals=True,
                    export_tangents=False,
                    export_materials='EXPORT',
                    export_cameras=False,
                    export_lights=False,
                    export_texture_dir="",           # ← Texturen direkt in export_dir
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

            print(f"  ✓ Exportiert: {filepath}")
            exported.append(safe_name + (".gltf" if export_format == 'GLTF' else
                                         ".glb"  if export_format == 'GLB'  else ".fbx"))

            bpy.ops.object.select_all(action='DESELECT')
            for obj in all_temp_objects:
                obj.select_set(True)
            bpy.ops.object.delete()

    for child in collection.children:
        print(f"\n--- Sub-Collection: {child.name} ---")
        export_collection(child)


for collection in scene.collection.children:
    print(f"\n=== Collection: {collection.name} ===")
    export_collection(collection)

print(f"\n{'='*50}")
print(f"Batch-Export abgeschlossen!")
print(f"  Exportiert: {len(exported)}")
for f in exported:
    print(f"    ✓ {f}")
if skipped:
    print(f"  Übersprungen: {len(skipped)}")
    for s in skipped:
        print(f"    - {s}")
print(f"  Zielordner: {export_dir}")
print(f"{'='*50}")
