import bpy, bmesh, math, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/logo.png"
TRANSPARENT = len(argv) > 1 and argv[1] == "transparent"
SAMPLES = int(argv[2]) if len(argv) > 2 else 128

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
try:
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = "GPU"
except Exception:
    pass
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 1024
scene.render.film_transparent = TRANSPARENT
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA" if TRANSPARENT else "RGB"
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Punchy"


def mat(name, color, metallic=0.0, rough=0.4, emit=None, strength=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.08
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def rounded_slab(name, w, h, depth, radius, edge, segs=24):
    """Rounded rectangle in XY extruded along Z, top/bottom edges softened."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(w, h, depth), verts=bm.verts)
    vertical = [e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).normalized().z) > 0.9]
    bmesh.ops.bevel(bm, geom=vertical, offset=radius, segments=segs, affect="EDGES", profile=0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bev = ob.modifiers.new("edge", "BEVEL")
    bev.width = edge
    bev.segments = 8
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(60)
    bev.harden_normals = True
    for p in me.polygons:
        p.use_smooth = True
    return ob


def cyl(name, r, d, loc, m, parent, bevel=0.012):
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=r, depth=d, location=loc)
    ob = bpy.context.object
    ob.name = name
    b = ob.modifiers.new("b", "BEVEL")
    b.width = bevel
    b.segments = 5
    b.limit_method = "ANGLE"
    bpy.ops.object.shade_smooth()
    ob.data.materials.append(m)
    ob.parent = parent
    return ob


# --- materials
body_m = mat("Body", (0.025, 0.027, 0.035), metallic=0.6, rough=0.28, coat=1.0)
face_m = mat("Face", (0.006, 0.007, 0.01), metallic=0.0, rough=0.55, coat=0.25)
key_m = mat("Key", (0.06, 0.065, 0.08), metallic=0.3, rough=0.32, coat=0.5)
glow_m = mat("Glow", (0.1, 0.6, 1.0), emit=(0.05, 0.55, 1.0), strength=3.5)
power_m = mat("Power", (1.0, 0.15, 0.2), emit=(1.0, 0.08, 0.12), strength=3.0)
ok_m = mat("OK", (0.55, 0.58, 0.65), metallic=1.0, rough=0.18)

# --- remote (built lying in XY plane, top face +Z)
root = bpy.data.objects.new("Remote", None)
bpy.context.collection.objects.link(root)

body = rounded_slab("Body", 1.25, 4.4, 0.32, 0.6, 0.1)
body.data.materials.append(body_m)
body.parent = root

face = rounded_slab("Face", 1.08, 4.22, 0.04, 0.52, 0.015)
face.location.z = 0.16
face.data.materials.append(face_m)
face.parent = root

top = 0.185
# power
cyl("Power", 0.13, 0.06, (0, 1.68, top), power_m, root, 0.02)
# d-pad: glowing ring + dark pad + metal OK
bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.03, major_segments=128,
                                 minor_segments=24, location=(0, 0.55, top + 0.01))
ring = bpy.context.object
bpy.ops.object.shade_smooth()
ring.data.materials.append(glow_m)
ring.parent = root
cyl("Pad", 0.38, 0.05, (0, 0.55, top), key_m, root, 0.015)
cyl("OK", 0.17, 0.08, (0, 0.55, top + 0.02), ok_m, root, 0.03)
# small keys grid
for i, y in enumerate((-0.45, -0.85, -1.25)):
    for x in (-0.27, 0.27):
        cyl(f"Key{i}{x}", 0.12, 0.05, (x, y, top), key_m, root, 0.018)
# volume rocker accent
vol = rounded_slab("Vol", 0.2, 0.62, 0.05, 0.095, 0.015, 12)
vol.location = (0, -1.78, top)
vol.data.materials.append(key_m)
vol.parent = root

# pose: tilt toward viewer, diagonal
root.rotation_euler = (math.radians(58), math.radians(0), math.radians(-24))
root.location = (0.05, 0.0, 0.0)

# --- background: gradient emission plane behind remote
if not TRANSPARENT:
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 6, 0), rotation=(math.radians(90), 0, 0))
    bg = bpy.context.object
    m = bpy.data.materials.new("BG")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Location"].default_value = (0.0, 0.08, 0)
    mp.inputs["Scale"].default_value = (2.8, 2.8, 1)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0.004, 0.008, 0.035, 1)
    cr.elements[1].position = 0.55
    cr.elements[1].color = (0.01, 0.09, 0.45, 1)
    e = cr.elements.new(1.0)
    e.color = (0.08, 0.45, 1.0, 1)
    nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
    # center the generated coords on the plane
    sub = nt.nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = (0.5, 0.5, 0.5)
    nt.links.new(tc.outputs["Generated"], sub.inputs[0])
    nt.links.new(sub.outputs[0], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs[0], out.inputs[0])
    bg.data.materials.append(m)
    bg.visible_shadow = False

# --- world (dim, slightly blue for reflections)
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.02, 0.03, 0.08, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6


def area(name, loc, target, power, size, color=(1, 1, 1)):
    l = bpy.data.lights.new(name, "AREA")
    l.energy = power
    l.size = size
    l.color = color
    ob = bpy.data.objects.new(name, l)
    bpy.context.collection.objects.link(ob)
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    l.cycles.is_portal = False
    ob.visible_camera = False
    return ob


area("Key", (-4, -5, 5), (0, 0, 0), 900, 4, (1.0, 0.97, 0.93))
area("Rim", (4, 3, 3), (0, 0, 0), 700, 3, (0.4, 0.65, 1.0))
area("Top", (0, -2, 7), (0, 0, 0), 250, 6)
area("Strip", (-3, 2, 1), (0, 0, 0), 400, 1.5, (0.6, 0.4, 1.0))

# --- camera
cam_d = bpy.data.cameras.new("Cam")
cam_d.lens = 85
cam = bpy.data.objects.new("Cam", cam_d)
bpy.context.collection.objects.link(cam)
cam.location = (0, -12.5, 1.0)
cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam

scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
