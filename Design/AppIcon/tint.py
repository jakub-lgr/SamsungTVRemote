import bpy, numpy as np, sys
src, dst = sys.argv[sys.argv.index("--")+1:]
img = bpy.data.images.load(src)
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
g = (px[:, 0]*0.2126 + px[:, 1]*0.7152 + px[:, 2]*0.0722) * px[:, 3]
g = np.clip(g * 1.6, 0, 1)
out = np.stack([g, g, g, np.ones_like(g)], 1)
o = bpy.data.images.new("t", w, h, alpha=False)
o.pixels[:] = out.ravel()
o.filepath_raw = dst; o.file_format = "PNG"
bpy.context.scene.render.image_settings.color_mode = "RGB"
o.save()
