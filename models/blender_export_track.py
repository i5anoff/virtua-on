import bpy
import bmesh
import argparse
import sys
import math
import mathutils
from mathutils import Vector, Matrix
from collections import defaultdict

# bpy.app.debug = True

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

epsilon = 0.001

def tohex(val, nbits):
    return (hex((int(round(val,0)) + (1<<nbits)) % (1<<nbits))[2:]).zfill(nbits>>2)

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

# short must be between -127/127
def pack_short(x):
    h = "{:02x}".format(int(round(x+128,0)))
    if len(h)!=2:
        raise Exception('Unable to convert: {} into a byte: {}'.format(x,h))
    return h

# float must be between -4/+3.968 resolution: 0.03125
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

genesis_to_p8_colors = {
    "1": 4, # dark brown
    "2": 7, # white
    "3": 8, # red
    "4": 1, # dark blue
    "5": 10, # yellow
    "6": 5, # dark grey
    "7": 13, # light bluish grey
    "8": 6, # light grey
    "9": 13, # dark bluish grey
    "a": 3, # dark green
    "b": 11, # light green
    "c": 3, # dark green
    "d": 15, # light yellow
    "e": 9, # dark yellow
    "f": 4, # brown
}

def voxel_bbox2d_intersects(i,j,w,b):
  return (abs(i - b[0]) * 2 < (w + b[2])) and (abs(j - b[1]) * 2 < (w + b[3]))

def verts_to_bbox2d(verts):
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    return (min(xs), min(ys), max(xs)-min(xs), max(ys)-min(ys))

def export_face(obcontext, f, loop_vert, inner_faces):
    fs = ""
    # default values
    is_dual_sided = False
    color = 0x11
    len_verts = len(f.loops)
    if len_verts>4:
        raise Exception('Face: {} has too many vertices: {}'.format(i,len_verts))
    if len(obcontext.material_slots)>0:
        slot = obcontext.material_slots[f.material_index]
        mat = slot.material
        is_dual_sided = mat.game_settings.use_backface_culling==False
        genesis_color = mat.name.split('_')[0]
        color = genesis_to_p8_colors[genesis_color[0]]*16 + genesis_to_p8_colors[genesis_color[1]]

    has_inner_faces = inner_faces is not None and len(inner_faces)>0
    # face flags bit layout:
    # inner faces:  8
    # track:        4 (todo)
    # tri/quad:     2
    # dual-side:    1
    fs += "{:02x}".format(
        (8 if has_inner_faces else 0) + 
        (2 if len_verts==4 else 0) + 
        (1 if is_dual_sided else 0))
    # color
    fs += "{:02x}".format(color)

    # + vertex id (= edge loop)
    for l in f.loops:
        vi = loop_vert[l.index]+1
        fs += pack_variant(vi)

    # inner faces?
    if has_inner_faces:
        fs += pack_variant(len(inner_faces))
        print("face: {} details: {}".format(f.index, len(inner_faces)))
        for inner_face in inner_faces:
            fs += export_face(obcontext, inner_face, loop_vert, None)

    return fs

def export_object(obcontext):
    # data
    s = ""
    obdata = obcontext.data
    bm = bmesh.new()
    bm.from_mesh(obdata)

    # create vertex group lookup dictionary for names
    vgroup_names = {vgroup.index: vgroup.name for vgroup in obcontext.vertex_groups}
    # create dictionary of vertex group assignments per vertex
    vgroups = {v.index: [vgroup_names[g.group] for g in v.groups] for v in obdata.vertices}

    # create a map loop index -> vertex index (see: https://www.python.org/dev/peps/pep-0274/)
    loop_vert = {l.index:l.vertex_index for l in obdata.loops}

    # vertices
    lens = pack_variant(len(obdata.vertices))
    s += lens
    for v in obdata.vertices:
        s += "{}{}{}".format(pack_double(v.co.x), pack_double(v.co.z), pack_double(v.co.y))

    # find detail vertices
    group_idx = obcontext.vertex_groups['DETAIL_FACE'].index
    group_verts = [v.index for v in obdata.vertices if group_idx in [ vg.group for vg in v.groups ] ]

    # find detail faces
    detail_faces = [f for f in bm.faces if len(f.verts)==len([v for v in f.verts if v.index in group_verts])]

    # all other faces
    other_faces = [f for f in bm.faces if f.index not in [f.index for f in detail_faces]]

    # map face index --> list of inner face indices
    inner_per_face = defaultdict(set)
    all_inner_faces = set()

    for f in detail_faces:
        # find similar normals
        for of in [of for of in other_faces if f.normal.dot(of.normal)>0.98]:
            v = of.verts[0].co - f.verts[0].co
            if abs(f.normal.dot(v))<0.01:  
                # print("{} <-coplanar-> {}".format(f.index, of.index))
                # inside?
                is_inside = True    
                for of_point in of.verts:
                    p0 = f.verts[len(f.verts)-1].co - of_point.co
                    # shared vertex?
                    if p0.length>epsilon:
                        for i_point in range(len(f.verts)):
                            p1 = f.verts[i_point].co - of_point.co
                            # shared vertex or colinear?
                            n = p0.cross(p1)
                            #print("p1: {} / n: {}".format(p1.length, n.length))
                            if p1.length>epsilon and n.length>0.02:
                                n.normalize()                 
                                if f.normal.dot(n)<-epsilon:
                                    is_inside = False
                                    break
                            p0 = p1.copy()
                    # stop checking this other face
                    if is_inside == False:
                        break
                # register inner face (excluded from direct export)
                if is_inside:
                    all_inner_faces.add(of.index)
                    inner_per_face[f.index].add(of)

    # faces (excluding inner faces)
    faces = []
    for f in [f for f in bm.faces if f.index not in all_inner_faces]:
        inner_faces = inner_per_face.get(f.index)
        if inner_faces and len(inner_faces)>127:
            raise Exception('Face: {} too many inner faces: {}'.format(f.index,len(inner_faces)))
        face_data = export_face(obcontext, f, loop_vert, inner_faces)
        faces.append({'face': f, 'data': face_data, 'bbox': verts_to_bbox2d(f.verts)})

    # push face data to buffer (inc. dual sided faces)
    print("Total faces: {} / inner faces: {}".format(len(faces), len(all_inner_faces)))
    s += pack_variant(len(faces))
    for i in range(len(faces)):
        s += faces[i]['data']
    
    # normals
    # same as face count
    for i in range(len(faces)):
        f = faces[i]['face']
        s += "{}{}{}".format(pack_float(f.normal.x), pack_float(f.normal.z), pack_float(f.normal.y))

    # voxels
    voxels=defaultdict(set)
    for v in bm.verts:
        pos_world = v.co
        x = (pos_world.x + 128)
        y = (pos_world.y + 128)
        if x<0 or y<0 or x>256 or y>256:
            raise Exception('Invalid vertex: {}'.format(pos_world))
        voxel = int(math.floor(x/8)) + 32*int(math.floor(y/8))
        if voxel<0 or voxel>32*32:
            raise Exception('Invalid voxel id: {} for {}/{}'.format(voxel,x,y))
        # find all overlapped faces
        # register in voxel
        for face in [f for f in v.link_faces if f.index not in all_inner_faces]:
            voxels[voxel].add(face.index)
    #
    # voxel_w = 8
    # voxel_planes = (
    #     Vector((0,0,0)),(0,-1,0),
    #     Vector((voxel_w,0,0)),(1,0,0),
    #     Vector((voxel_w,voxel_w,0)),(0,1,0),
    #     Vector((0,voxel_w,0)),(-1,0,0)
    # )
    # # ref: https://blender.stackexchange.com/questions/75845/wrong-shading-as-a-result-of-bisect-plane-in-bmesh
    # for i in range(len(faces)):
    #     f = faces[i]['face']
    #     fbox = faces[i]['bbox']
    #     for vi in range(32):
    #         vx = vi-128
    #         for vj in range(32):
    #             vy = vj-128
    #             if voxel_bbox2d_intersects(vx,vy,voxel_w,fbox):
    #                 fmesh = bmesh.ops.duplicate(bm, geom=f.verts[:] + f.edges[:] + (f))

    #                 # clip face against voxel borders
    #                 for (plane_co, plane_no) in voxel_planes:
    #                     voxel_p = plane_co + (vx,vy,0)
    #                     voxel_n = plane_no
    #                     res = bmesh.ops.bisect_plane(fmesh, geom = fmesh.verts[:] + fmesh.edges[:] + fmesh.faces[:], dist = 0, plane_co = voxel_p,plane_no = voxel_n, clear_outer = True)
    #                     fmesh.ops.split_edges(fmesh, edges=[e for e in ret['geom_cut'] if isinstance(e, bmesh.types.BMEdge)])                
    #                 # any match
    #                 if len(fmesh.verts)>0:
    #                     voxel_id = vi + 32*vj
    #                     print("voxel[{}] += face: {}".format(voxel_id,face.index))
    #                     voxels[voxel_id].add(face.index)

    # export voxels
    # number of cells
    s += pack_variant(len(voxels.keys()))
    for k,v in voxels.items():
        # voxel ID
        s += pack_variant(k)
        # number of faces
        if len(v)>255:
            raise Exception('Voxel: {}/{} has too many faces: {}'.format(voxel%32,round(k/32,0),len(v)))
        s += pack_variant(len(v))
        # face indices
        for i in v:
            s += pack_variant(i+1)

    return s

# model data
s = ""

# select first mesh object
obcontext = [o for o in scene.objects if o.type == 'MESH' and o.layers[0]][0]

# object name
name = obcontext.name.lower()
s = s + "{:02x}".format(len(name))
for c in name:
    s = s + "{:02x}".format(charset.index(c)+1)

# scale (custom scene property)
model_scale = scene.get("scale", 1)
s = s + "{:02x}".format(model_scale)

s = s + export_object(obcontext)

#
with open(args.out, 'w') as f:
    f.write(s)

