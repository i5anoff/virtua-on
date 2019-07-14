import bpy
import bmesh
import argparse
import sys
import math
from mathutils import Vector, Matrix
from collections import defaultdict

argv = sys.argv
if "--" not in argv:
    argv = []
else:
   argv = argv[argv.index("--") + 1:]

try:
    parser = argparse.ArgumentParser(description='Exports Blender model as a byte array for wireframe rendering',prog = "blender -b -P "+__file__+" --")
    parser.add_argument('-o','--out', help='Output file', required=True, dest='out')
    args = parser.parse_args(argv)
except Exception as e:
    sys.exit(repr(e))

scene = bpy.context.scene

# charset
charset="_0123456789abcdefghijklmnopqrstuvwxyz"

def tohex(val, nbits):
    return (hex((int(round(val,0)) + (1<<nbits)) % (1<<nbits))[2:]).zfill(nbits>>2)

def pack_string(name):
    name = name.lower()
    s = "{:02x}".format(len(name))
    for c in name:
        s += "{:02x}".format(charset.index(c)+1)
    return s

# variable length packing (1 or 2 bytes)
def pack_variant(x):
    if x>0x7fff:
      raise Exception('Unable to convert: {} into a 1 or 2 bytes'.format(x))
    # 2 bytes
    if x>127:
        h = "{:04x}".format(x + 0x8000)
        if len(h)!=4:
            raise Exception('Unable to convert: {} into a word: {}'.format(x,h))
        return h
    # 1 byte
    h = "{:02x}".format(x)
    if len(h)!=2:
        raise Exception('Unable to convert: {} into a byte: {}'.format(x,h))
    return h

# float must be between -3.2/+3.2
def pack_float(x):
    h = "{:02x}".format(int(round(32*x+128,0)))
    if len(h)!=2:
        raise Exception('Unable to convert: {} into a byte: {}'.format(x,h))
    return h
# double must be between -128/+127 resolution: 0.0078
def pack_double(x):
    h = "{}".format(tohex(128*x+16384,16))
    if len(h)!=4:
        raise Exception('Unable to convert: {} into a word: {}'.format(x,h))
    return h

p8_colors = ['000000','1D2B53','7E2553','008751','AB5236','5F574F','C2C3C7','FFF1E8','FF004D','FFA300','FFEC27','00E436','29ADFF','83769C','FF77A8','FFCCAA']
def diffuse_to_p8color(rgb):
    h = "{:02X}{:02X}{:02X}".format(int(round(255*rgb.r)),int(round(255*rgb.g)),int(round(255*rgb.b)))
    try:
        #print("diffuse:{} -> {}\n".format(rgb,p8_colors.index(h)))
        return p8_colors.index(h)
    except Exception as e:
        # unknown color
        raise Exception('Unknown color: 0x{}'.format(h))

def find_faces_by_group(bm, obcontext, name):
    if name in obcontext.vertex_groups:
        obdata = obcontext.data
        group_idx = obcontext.vertex_groups[name].index
        group_verts = [v.index for v in obdata.vertices if group_idx in [ vg.group for vg in v.groups ] ]

        return [f for f in bm.faces if len(f.verts)==len([v for v in f.verts if v.index in group_verts])]   

def export_layer(scale,l):
    # data
    s = ""
    layer = [ob for ob in scene.objects if ob.layers[l]]
    if len(layer)>0:
        obcontext = [o for o in layer if o.type == 'MESH'][0]
        obdata = obcontext.data
        bm = bmesh.new()
        bm.from_mesh(obdata)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        bm.normal_update()

        # vertex groups
        vgroup_names = {vgroup.index: vgroup.name for vgroup in obcontext.vertex_groups}
        # group id -> set(vertex.index)
        vgroups = defaultdict(set)
        for v in obdata.vertices:
            if len(v.groups)>1:
                raise Exception('Vertex: {} shared by more than 1 ({}) vertex group.'.format(v.index, len(v.groups)))
            if len(v.groups)==1:
                vgroups[v.groups[0].group].add(v.index)
        
        # vgroup centers
        # vertex id -> cg
        vgroup_cgs = {}
        # group index -> cg
        vgroup_cgs_by_name = {}
        for k,v in vgroups.items():
            # group position
            cg = Vector((0,0,0))
            for p in [obdata.vertices[vi] for vi in v]:
                cg += p.co
            cg /= len(v)
            for vi in v:
                vgroup_cgs[vi] = cg
            vgroup_cgs_by_name[vgroup_names[k]] = cg
        
        # vertex index -> group 
        vgroups = { v.index: vgroup_names[v.groups[0].group] for v in obdata.vertices if len(v.groups)>0 }

        vlen = len(obdata.vertices)
        # vertices
        s += pack_variant(vlen)
        for v in obdata.vertices:
            pos = v.co.copy()
            # offset vertex groups
            if v.index in vgroup_cgs:
                pos -= vgroup_cgs[v.index]
            s += "{}{}{}".format(pack_double(pos.x), pack_double(pos.z), pack_double(pos.y))

        # faces
        faces = []
        vgroup_faces = defaultdict(list)
        for f in bm.faces:
            fs = ""
            color = "11" # hex 0x11
            is_dual_sided = False     
            len_verts = len(f.verts)
            if len_verts>4:
                raise Exception('Face: {} has too many vertices: {}'.format(i,len_verts))
            # color / dual sided flag     
            if len(obcontext.material_slots)>0:
                slot = obcontext.material_slots[f.material_index]
                mat = slot.material
                is_dual_sided = mat.game_settings.use_backface_culling==False
                # colors are encoded as hex figures in Blender!
                color = mat.name.split('_')[0]

            # face flags bit layout:
            # 1: tri/quad
            # 0: dual-side
            fs += "{:02x}".format(
                (2 if len_verts==4 else 0) + 
                (1 if is_dual_sided else 0))
            # color
            fs += color

            # + vertex id
            vgroup_name = None
            for l in f.loops:
                vi = l.vert.index
                fs += "{:02x}".format(vi+1)
                # if v belongs to group -> move face to vertex group
                v = obdata.vertices[vi]
                if len(v.groups)>=1:
                    vgroup_name = vgroup_names[v.groups[0].group]
            face_data = {'index': f.index, 'data': fs}
            
            if vgroup_name is None:
                faces.append(face_data)
            else:
                vgroup_faces[vgroup_name].append(face_data)

        # push face data to buffer (inc. dual sided faces)
        s += "{:02x}".format(len(faces))
        for f in faces:
            s += f['data']
            raw_face = bm.faces[f['index']]
            # normal
            s += "{}{}{}".format(pack_double(raw_face.normal.x), pack_double(raw_face.normal.z), pack_double(raw_face.normal.y))
                
        s += pack_variant(len(vgroup_faces.keys()))
        for k,faces in vgroup_faces.items():
            # group name
            s += pack_string(k)
            # group position
            cg = vgroup_cgs_by_name[k]
            s += "{}{}{}".format(pack_double(cg.x), pack_double(cg.z), pack_double(cg.y))
            # number of index
            s += pack_variant(len(faces))
            for f in faces:
                s += f['data']
                raw_face = bm.faces[f['index']]
                # normal
                s += "{}{}{}".format(pack_double(raw_face.normal.x), pack_double(raw_face.normal.z), pack_double(raw_face.normal.y))
    return s

# model data
s = ""

# select first mesh object
obcontext = [o for o in scene.objects if o.type == 'MESH' and o.layers[0]][0]

# object name
name = obcontext.name
s += pack_string(name)

# scale (custom scene property)
model_scale = scene.get("scale", 1)
s += "{:02x}".format(model_scale)

# model lod selection (+ default value)
lod_dist = scene.get("lod_dist", [32])
s += "{:02x}".format(len(lod_dist))
for i in lod_dist:
    s += "{}".format(pack_double(i))

# layers = lod
ln = 0
ls = ""
for i in range(3):
    layer_data = export_layer(model_scale,i)
    if len(layer_data)>0:
        ln += 1
        ls = ls + layer_data
# number of active lods
s += "{:02x}".format(ln)
s += ls

#
with open(args.out, 'w') as f:
    f.write(s)

