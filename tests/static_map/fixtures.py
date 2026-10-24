#!/usr/bin/env python3
"""Deterministic tiny assets; no downloaded models or robots."""
import base64,json,pathlib,struct,sys
p=pathlib.Path(sys.argv[1]);p.mkdir(parents=True,exist_ok=True)
verts=[(-.5,-.5,-.5),(.5,-.5,-.5),(.5,.5,-.5),(-.5,.5,-.5),(-.5,-.5,.5),(.5,-.5,.5),(.5,.5,.5),(-.5,.5,.5)]
faces=[(0,2,1),(0,3,2),(4,5,6),(4,6,7),(0,1,5),(0,5,4),(3,7,6),(3,6,2),(0,4,7),(0,7,3),(1,2,6),(1,6,5)]
def obj(name,boxes,mtl=False):
 lines=['mtllib surface.mtl','usemtl surface'] if mtl else []
 for n,(c,s) in enumerate(boxes):
  for v in verts:lines.append('v '+' '.join(str(c[i]+v[i]*s[i]) for i in range(3)))
  for face in faces:lines.append('f '+' '.join(str(n*8+i+1) for i in face))
 (p/name).write_text('\n'.join(lines)+'\n')
obj('box.obj',[((0,0,0),(1,1,1))],True)
(p/'surface.mtl').write_text('newmtl surface\nKd .7 .3 .2\nmap_Kd missing.png\n')
(p/'.gdignore').touch()
# Explicit parts preserve the door opening. Whole-building convex hull is forbidden.
room=[((0,-.1,0),(6,.2,6)),((-2,1.5,-3),(2,3,.2)),((2,1.5,-3),(2,3,.2)),((0,2.6,-3),(2,.8,.2)),((0,1.5,3),(6,3,.2)),((-3,1.5,0),(.2,3,6)),((3,1.5,0),(.2,3,6))]
obj('room.obj',room)
stairs=[((i*.5,.125*(i+1),0),(.5,.25*(i+1),1)) for i in range(5)]
obj('stairs.obj',stairs)
(p/'parts.json').write_text(json.dumps({'room':[{'center':c,'size':s} for c,s in room],'stairs':[{'center':c,'size':s} for c,s in stairs]}))
(p/'bad.obj').write_text('v 0 0 0\nf 1 4 9\n')
(p/'ngon.obj').write_text('v 0 0 0\nf 1 1 1 1\n')
(p/'bad.stl').write_bytes(b'not an stl')
(p/'box.stl').write_text('solid box\n'+''.join('facet normal 0 0 0\nouter loop\n'+''.join('vertex '+' '.join(str(x*1000) for x in verts[i])+'\n' for i in f)+'endloop\nendfacet\n' for f in faces)+'endsolid box\n')
binary=b'geometry-only'.ljust(80,b'\0')+struct.pack('<I',len(faces))+b''.join(struct.pack('<12fH',0,0,0,*(x for i in f for x in verts[i]),0) for f in faces)
(p/'box_binary.stl').write_bytes(binary)
positions=b''.join(struct.pack('<3f',*v) for v in verts); indices=b''.join(struct.pack('<3H',*f) for f in faces);blob=positions+indices
base={'asset':{'version':'2.0'},'buffers':[{'byteLength':len(blob),'uri':'box.bin'}],'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':len(positions)},{'buffer':0,'byteOffset':len(positions),'byteLength':len(indices)}],'accessors':[{'bufferView':0,'componentType':5126,'count':8,'type':'VEC3','min':[-.5]*3,'max':[.5]*3},{'bufferView':1,'componentType':5123,'count':36,'type':'SCALAR'}],'materials':[{'pbrMetallicRoughness':{'baseColorFactor':[.3,.7,.4,1],'metallicFactor':0,'roughnessFactor':.8}}],'meshes':[{'primitives':[{'attributes':{'POSITION':0},'indices':1,'material':0}]}],'nodes':[{'name':'Parent','translation':[2,3,4],'children':[1]},{'name':'Asymmetric','mesh':0,'translation':[1,0,0],'scale':[1,2,3]}],'scenes':[{'nodes':[0]}],'scene':0}
(p/'box.bin').write_bytes(blob);(p/'hierarchy.gltf').write_text(json.dumps(base))
base['nodes']=[{'name':'Calibration','mesh':0}];base['buffers'][0].pop('uri');js=json.dumps(base,separators=(',',':')).encode();js+=b' '*((-len(js))%4);blob+=b'\0'*((-len(blob))%4)
(p/'box.glb').write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob)
base['buffers'][0]['uri']='absent.bin';(p/'missing.gltf').write_text(json.dumps(base));(p/'bad.glb').write_bytes(b'broken')
(p/'ramp.raw').write_bytes(struct.pack('<6f',-1,0,1,-1,0,1));(p/'ramp.json').write_text(json.dumps([-1,0,1,-1,0,1]))
contract={'file':'ramp.raw','width':3,'depth':2,'spacing_x':1,'spacing_z':1,'unit':'m','row_order':'increasing_z','encoding':'float32_le'}
(p/'ramp.height.json').write_text(json.dumps(contract))
(p/'include.xml').write_text('<mujoco><geom name="floor" type="box" size="3 3 .1"/></mujoco>')
(p/'main.xml').write_text('<mujoco><worldbody><include file="include.xml"/></worldbody></mujoco>')
(p/'bad.xml').write_text('<mujoco><worldbody><geom type="nonsense"/></worldbody></mujoco>')
# Actual texture bytes exercise dependency tracking and embedding; no image libraries required.
import zlib,binascii

def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',binascii.crc32(kind+data)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',2,2,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b'\0'+b'\xff\x80\x40'*2+b'\0'+b'\xff\x80\x40'*2))+chunk(b'IEND',b'')
(p/'texture.png').write_bytes(png)
(p/'texture.mtl').write_text('newmtl surface\nKd 1 1 1\nmap_Kd texture.png\n')
(p/'room.obj').write_text('mtllib texture.mtl\nusemtl surface\n'+(p/'room.obj').read_text())
(p/'asset.xml').write_text('<mujoco><asset><mesh name="cube" file="box.obj"/><texture name="texture" type="2d" file="texture.png"/><material name="surface" texture="texture"/></asset><worldbody><geom type="mesh" mesh="cube" material="surface"/></worldbody></mujoco>')

(p/"box_tabs_crlf.stl").write_bytes((p/"box.stl").read_text().replace(" ","\t").replace("\n","\r\n").encode())
